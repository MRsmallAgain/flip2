#!/usr/bin/env python3
"""Contacts check and message rebuild for Flip 2 personal backups.

Stdout is one JSON object of integer counts plus a fixed kind string.
Names, phone numbers, message bodies, and snippets are never printed.
A contacts file is only snapshotted. A message file is rebuilt: threads
are inserted before SMS rows because the stock insert triggers only
update an existing thread and copy the body into threads.snippet.
PDU, part, and addr rows are left empty so attachments stay out.
"""

import json
import os
import re
import sqlite3
import sys

CONTACTS_VERSION = 1401
MESSAGES_VERSION = 670020
IDENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
SMS_FIELDS = (
    'address', 'date', 'date_sent', 'protocol', 'read', 'status', 'type',
    'reply_path_present', 'subject', 'body', 'service_center', 'locked',
    'sub_id', 'error_code', 'creator', 'seen', 'ipmsg_id',
)


def bin_cmp(a, b):
    if a is None and b is None:
        return 0
    if a is None:
        return -1
    if b is None:
        return 1
    if not isinstance(a, str):
        a = str(a)
    if not isinstance(b, str):
        b = str(b)
    return (a > b) - (a < b)


def register(conn):
    # PHONEBOOK has to exist before the first read. A missing collation is
    # how a contacts rewrite previously stored blank names.
    for name in ('PHONEBOOK', 'LOCALIZED', 'UNICODE'):
        conn.create_collation(name, bin_cmp)


def connect(path, query_only):
    conn = sqlite3.connect(path)
    register(conn)
    conn.row_factory = sqlite3.Row
    if query_only:
        conn.execute('PRAGMA query_only = ON')
    return conn


def safe_error(err):
    text = str(err).replace('\n', ' ')
    if len(text) > 160 or sum(ch.isdigit() for ch in text) >= 7:
        return type(err).__name__
    return type(err).__name__ + ': ' + text


def emit(kind, counts):
    if kind not in ('contacts', 'messages', 'snapshot'):
        raise SystemExit('bad kind')
    out = {'kind': kind}
    for key, value in counts.items():
        if not isinstance(key, str) or not key.isidentifier():
            raise SystemExit('bad count name')
        if isinstance(value, bool) or not isinstance(value, int):
            raise SystemExit('refusing non-count output')
        out[key] = value
    sys.stdout.write(json.dumps(out, sort_keys=True) + '\n')


def ident(name):
    if not IDENT.fullmatch(name or ''):
        raise SystemExit('unexpected sqlite name')
    return name


def columns(conn, table):
    return [row[1] for row in conn.execute('PRAGMA table_info(' + ident(table) + ')')]


def table_exists(conn, table):
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    ).fetchone()
    return row is not None


def as_text(value):
    if value is None:
        return ''
    if isinstance(value, bytes):
        return value.decode('utf-8', 'replace')
    return str(value)


def to_ms(value):
    if value is None:
        return 0
    number = int(value)
    if number < 1000000000000:
        return number * 1000
    return number


def insert_row(conn, table, overrides):
    table = ident(table)
    if table not in ('sms', 'threads', 'canonical_addresses', 'thread_settings', 'android_metadata'):
        raise SystemExit('refusing table')
    info = list(conn.execute('PRAGMA table_info(' + table + ')'))
    known = {col[1] for col in info}
    use = {key: value for key, value in overrides.items() if key in known}
    names = []
    values = []
    for _cid, name, typ, notnull, default, pk in info:
        if name in use:
            names.append(name)
            values.append(use[name])
        elif notnull and default is None and not (pk and name == '_id'):
            names.append(name)
            values.append(0 if typ and 'INT' in typ.upper() else '')
    sql = 'INSERT INTO ' + table + ' (' + ','.join(names) + ') VALUES (' + ','.join('?' * len(names)) + ')'
    conn.execute(sql, values)


def check_contacts(path):
    conn = connect(path, True)
    try:
        if 'display_name' not in columns(conn, 'raw_contacts'):
            raise SystemExit('missing column raw_contacts.display_name')
        user_version = int(conn.execute('PRAGMA user_version').fetchone()[0])
        raw, blank = conn.execute(
            'SELECT '
            '(SELECT COUNT(*) FROM raw_contacts), '
            "(SELECT COUNT(*) FROM raw_contacts WHERE display_name IS NULL OR TRIM(display_name) = '')"
        ).fetchone()
        contacts = int(conn.execute('SELECT COUNT(*) FROM contacts').fetchone()[0])
        data = int(conn.execute('SELECT COUNT(*) FROM data').fetchone()[0])
        names = int(conn.execute(
            'SELECT COUNT(*) FROM data d '
            'JOIN mimetypes m ON d.mimetype_id = m._id '
            "WHERE m.mimetype = 'vnd.android.cursor.item/name'"
        ).fetchone()[0])
        phones = int(conn.execute(
            'SELECT COUNT(*) FROM data d '
            'JOIN mimetypes m ON d.mimetype_id = m._id '
            "WHERE m.mimetype = 'vnd.android.cursor.item/phone_v2'"
        ).fetchone()[0])
        accounts = int(conn.execute('SELECT COUNT(*) FROM accounts').fetchone()[0]) if table_exists(conn, 'accounts') else 0
        return {
            'userVersion': user_version,
            'contacts': contacts,
            'raw': int(raw),
            'blankNames': int(blank),
            'named': int(raw) - int(blank),
            'data': data,
            'names': names,
            'phones': phones,
            'accounts': accounts,
        }
    finally:
        conn.close()


def fixture_contacts(counts):
    expect = {
        'userVersion': CONTACTS_VERSION,
        'contacts': 18,
        'raw': 18,
        'blankNames': 0,
        'named': 18,
        'data': 36,
        'names': 18,
        'phones': 18,
        'accounts': 6,
    }
    return [key for key, value in expect.items() if counts.get(key) != value]


def choose_address(addr_rows, box):
    want = 137 if box == 1 else 151
    chosen = []
    for row in addr_rows:
        if row['type'] != want:
            continue
        text = as_text(row['address']).strip()
        if not text:
            continue
        chosen.append((row['_id'], text))
    chosen.sort(key=lambda item: item[0])
    if not chosen:
        return '', 0
    return chosen[0][1], len(chosen)


def load_messages(src):
    user_version = int(src.execute('PRAGMA user_version').fetchone()[0])
    for required in ('_id', 'date', 'msg_box'):
        if required not in columns(src, 'pdu'):
            raise SystemExit('missing column pdu.' + required)
    for required in ('mid', 'ct', 'text'):
        if required not in columns(src, 'part'):
            raise SystemExit('missing column part.' + required)
    for required in ('_id', 'msg_id', 'type', 'address'):
        if required not in columns(src, 'addr'):
            raise SystemExit('missing column addr.' + required)
    pdu_cols = set(columns(src, 'pdu'))
    pdu_sql = 'SELECT _id, date, msg_box' + (', date_sent' if 'date_sent' in pdu_cols else '') + ' FROM pdu'
    pdus = {row['_id']: row for row in src.execute(pdu_sql)}
    by_msg = {}
    for row in src.execute('SELECT _id, msg_id, type, address FROM addr'):
        by_msg.setdefault(row['msg_id'], []).append(row)
    grouped = {}
    text_parts = 0
    for row in src.execute('SELECT mid, ct, text FROM part'):
        if as_text(row['ct']).split(';')[0].strip().lower() != 'text/plain':
            continue
        if not as_text(row['text']).strip():
            continue
        text_parts += 1
        grouped.setdefault(row['mid'], []).append(as_text(row['text']))
    sms_have = set(columns(src, 'sms'))
    use = [name for name in SMS_FIELDS if name in sms_have]
    sms_rows = src.execute('SELECT ' + ','.join(use) + ' FROM sms').fetchall()
    items = []
    original_inbox = 0
    original_sent = 0
    original_ms = 0
    for row in sms_rows:
        address = as_text(row['address']).strip() if 'address' in row.keys() else ''
        date = int(row['date'] or 0) if 'date' in row.keys() else 0
        if date >= 1000000000000:
            original_ms += 1
        msg_type = int(row['type'] or 0) if 'type' in row.keys() else 0
        if msg_type == 1:
            original_inbox += 1
        elif msg_type == 2:
            original_sent += 1
        fields = {}
        for name in use:
            if name in ('address', 'date', 'date_sent', 'type', 'body'):
                continue
            fields[name] = row[name]
        items.append({
            'origin': 'sms',
            'address': address,
            'date': date,
            'date_sent': int(row['date_sent'] or 0) if 'date_sent' in row.keys() else 0,
            'type': msg_type,
            'body': as_text(row['body']) if 'body' in row.keys() else '',
            'fields': fields,
        })
    part_inbox = 0
    part_sent = 0
    part_ms = 0
    skipped_box = 0
    skipped_no_address = 0
    multi_addr_sent = 0
    multi_addr_inbox = 0
    for mid, chunks in grouped.items():
        pdu = pdus.get(mid)
        if pdu is None:
            skipped_no_address += 1
            continue
        box = int(pdu['msg_box'] or 0)
        if box not in (1, 2):
            skipped_box += 1
            continue
        address, n_cands = choose_address(by_msg.get(mid, []), box)
        if not address:
            skipped_no_address += 1
            continue
        if n_cands > 1 and box == 2:
            multi_addr_sent += 1
        if n_cands > 1 and box == 1:
            multi_addr_inbox += 1
        date = to_ms(pdu['date'])
        date_sent = to_ms(pdu['date_sent']) if 'date_sent' in pdu.keys() else date
        if date >= 1000000000000:
            part_ms += 1
        if box == 1:
            part_inbox += 1
        else:
            part_sent += 1
        items.append({
            'origin': 'part',
            'address': address,
            'date': date,
            'date_sent': date_sent,
            'type': box,
            'body': '\n'.join(chunks),
            'fields': {
                'read': 1,
                'seen': 1,
                'status': -1,
                'protocol': 0,
                'reply_path_present': 0,
                'locked': 0,
                'sub_id': -1,
                'error_code': 0,
            },
        })
    source_threads = int(src.execute('SELECT COUNT(*) FROM threads').fetchone()[0]) if table_exists(src, 'threads') else 0
    source_canonical = int(src.execute('SELECT COUNT(*) FROM canonical_addresses').fetchone()[0]) if table_exists(src, 'canonical_addresses') else 0
    meta = {
        'userVersion': user_version,
        'original': len(sms_rows),
        'originalInbox': original_inbox,
        'originalSent': original_sent,
        'originalMs': original_ms,
        'textParts': text_parts,
        'partInbox': part_inbox,
        'partSent': part_sent,
        'partMs': part_ms,
        'skippedBox': skipped_box,
        'skippedNoAddress': skipped_no_address,
        'multiAddrSent': multi_addr_sent,
        'multiAddrInbox': multi_addr_inbox,
        'sourceThreads': source_threads,
        'sourceCanonical': source_canonical,
    }
    return items, meta


def copy_schema(src, dst):
    rows = src.execute(
        "SELECT type, name, sql FROM sqlite_master "
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    order = {'table': 0, 'index': 1, 'view': 2, 'trigger': 3}
    rows = [row for row in rows if row['type'] in order]
    rows.sort(key=lambda row: (order[row['type']], row['name']))
    failed = set()
    triggers = 0
    for row in rows:
        name = row['name']
        if not IDENT.fullmatch(name or ''):
            continue
        sql = row['sql']
        if row['type'] != 'table' and any(re.search(r'\b' + re.escape(skip) + r'\b', sql) for skip in failed):
            continue
        try:
            dst.execute(sql)
        except sqlite3.OperationalError:
            if row['type'] == 'table':
                failed.add(name)
            continue
        if row['type'] == 'trigger':
            triggers += 1
    for required in ('sms', 'threads', 'canonical_addresses', 'pdu', 'part'):
        if not table_exists(dst, required):
            raise SystemExit('message schema is incomplete')
    return triggers


def copy_locale(src, dst):
    if not table_exists(src, 'android_metadata') or not table_exists(dst, 'android_metadata'):
        return
    cols = columns(src, 'android_metadata')
    if any(name not in ('_id', 'locale') for name in cols):
        return
    if 'locale' not in cols:
        return
    for row in src.execute('SELECT locale FROM android_metadata'):
        loc = row[0]
        if not isinstance(loc, str) or len(loc) > 32:
            continue
        try:
            insert_row(dst, 'android_metadata', {'locale': loc})
        except sqlite3.Error:
            return


def build_messages(src_path, dst_path):
    src = connect(src_path, True)
    try:
        items, meta = load_messages(src)
        if os.path.exists(dst_path):
            os.remove(dst_path)
        dst = sqlite3.connect(dst_path)
        register(dst)
        try:
            dst.execute('PRAGMA foreign_keys = OFF')
            dst.execute('PRAGMA journal_mode = DELETE')
            triggers = copy_schema(src, dst)
            dst.execute('PRAGMA user_version = ' + str(MESSAGES_VERSION))
            try:
                copy_locale(src, dst)
            except sqlite3.Error:
                pass
            order = []
            spelling = {}
            for item in items:
                key = item['address'].strip()
                if key not in spelling:
                    spelling[key] = item['address']
                    order.append(key)
            thread_of = {}
            for index, key in enumerate(order, start=1):
                thread_of[key] = index
                insert_row(dst, 'canonical_addresses', {'_id': index, 'address': spelling[key]})
                insert_row(dst, 'threads', {
                    '_id': index,
                    'date': 0,
                    'date_sent': 0,
                    'message_count': 0,
                    'readcount': 0,
                    'recipient_ids': str(index),
                    'snippet': '',
                    'snippet_cs': 0,
                    'read': 1,
                    'archived': 0,
                    'type': 0,
                    'error': 0,
                    'has_attachment': 0,
                    'attachment_info': '',
                    'status': 0,
                })
            if table_exists(dst, 'thread_settings'):
                have = dst.execute('SELECT COUNT(*) FROM thread_settings').fetchone()[0]
                if int(have) == 0:
                    for index in range(1, len(order) + 1):
                        insert_row(dst, 'thread_settings', {
                            'thread_id': index,
                            'spam': 0,
                            'notification_enable': 1,
                            'mute': 0,
                            'mute_start': 0,
                            'ringtone': '',
                            '_data': '',
                            'vibrate': 1,
                        })
            items.sort(key=lambda item: item['date'])
            for item in items:
                overrides = dict(item['fields'])
                overrides.update({
                    'thread_id': thread_of[item['address'].strip()],
                    'address': item['address'],
                    'date': item['date'],
                    'date_sent': item['date_sent'],
                    'type': item['type'],
                    'body': item['body'],
                })
                insert_row(dst, 'sms', overrides)
            if 'message_count' in columns(dst, 'threads'):
                dst.execute(
                    'UPDATE threads SET '
                    'message_count = (SELECT COUNT(*) FROM sms s WHERE s.thread_id = threads._id), '
                    'readcount = (SELECT COUNT(*) FROM sms s WHERE s.thread_id = threads._id AND s.read = 1), '
                    'date = COALESCE((SELECT MAX(s.date) FROM sms s WHERE s.thread_id = threads._id), 0), '
                    'date_sent = COALESCE((SELECT MAX(s.date_sent) FROM sms s WHERE s.thread_id = threads._id), 0)'
                )
            if 'snippet' in columns(dst, 'threads'):
                dst.execute(
                    'UPDATE threads SET snippet = COALESCE(('
                    'SELECT s.body FROM sms s WHERE s.thread_id = threads._id '
                    'ORDER BY s.date DESC LIMIT 1), \'\')'
                )
            if 'has_attachment' in columns(dst, 'threads'):
                dst.execute('UPDATE threads SET has_attachment = 0')
            dst.commit()
            user_version = int(dst.execute('PRAGMA user_version').fetchone()[0])
            sms = int(dst.execute('SELECT COUNT(*) FROM sms').fetchone()[0])
            inbox = int(dst.execute('SELECT COUNT(*) FROM sms WHERE type = 1').fetchone()[0])
            sent = int(dst.execute('SELECT COUNT(*) FROM sms WHERE type = 2').fetchone()[0])
            ms_dates = int(dst.execute('SELECT COUNT(*) FROM sms WHERE date >= 1000000000000').fetchone()[0])
            pdu = int(dst.execute('SELECT COUNT(*) FROM pdu').fetchone()[0])
            part = int(dst.execute('SELECT COUNT(*) FROM part').fetchone()[0])
            threads = int(dst.execute('SELECT COUNT(*) FROM threads').fetchone()[0])
            distinct = int(dst.execute('SELECT COUNT(*) FROM canonical_addresses').fetchone()[0])
            digit_keys = set()
            for key in order:
                digits = ''.join(ch for ch in spelling[key] if ch.isdigit())
                if len(digits) == 11 and digits.startswith('1'):
                    digits = digits[1:]
                digit_keys.add(digits or key)
            counts = dict(meta)
            counts.update({
                'userVersion': user_version,
                'sms': sms,
                'fromParts': part_inbox_sent(meta),
                'inbox': inbox,
                'sent': sent,
                'msDates': ms_dates,
                'pdu': pdu,
                'part': part,
                'threads': threads,
                'distinctAddresses': distinct,
                'distinctDigitKeys': len(digit_keys),
                'triggers': triggers,
            })
            return counts
        except Exception:
            try:
                dst.close()
            except sqlite3.Error:
                pass
            if os.path.exists(dst_path):
                os.remove(dst_path)
            raise
        finally:
            dst.close()
    finally:
        src.close()


def part_inbox_sent(meta):
    return int(meta.get('partInbox', 0)) + int(meta.get('partSent', 0))


def fixture_messages(counts):
    expect = {
        'userVersion': MESSAGES_VERSION,
        'sms': 84,
        'original': 51,
        'originalInbox': 32,
        'originalSent': 19,
        'originalMs': 51,
        'textParts': 33,
        'fromParts': 33,
        'partInbox': 29,
        'partSent': 4,
        'partMs': 33,
        'inbox': 61,
        'sent': 23,
        'msDates': 84,
        'pdu': 0,
        'part': 0,
        'skippedNoAddress': 0,
        'skippedBox': 0,
        'multiAddrSent': 4,
        'multiAddrInbox': 0,
        'sourceThreads': 6,
        'sourceCanonical': 7,
    }
    bad = [key for key, value in expect.items() if counts.get(key) != value]
    if counts.get('threads') == counts.get('sourceThreads'):
        bad.append('threads-copied')
    if counts.get('threads') != counts.get('distinctAddresses'):
        bad.append('threads-vs-addresses')
    return bad


def snapshot(src_path, dst_path):
    src = connect(src_path, False)
    try:
        try:
            src.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        except sqlite3.Error:
            pass
        if os.path.exists(dst_path):
            os.remove(dst_path)
        dst = sqlite3.connect(dst_path)
        register(dst)
        try:
            src.backup(dst)
            dst.commit()
            user_version = int(dst.execute('PRAGMA user_version').fetchone()[0])
        finally:
            dst.close()
        return {'userVersion': user_version, 'bytes': os.path.getsize(dst_path)}
    finally:
        src.close()


def main(argv):
    if len(argv) < 2:
        raise SystemExit('usage: personal_db.py check-contacts|build-messages|snapshot ...')
    cmd = argv[0]
    fixture = '--fixture' in argv
    args = [arg for arg in argv[1:] if arg != '--fixture']
    if cmd == 'check-contacts':
        if len(args) != 1:
            raise SystemExit('usage: check-contacts FILE [--fixture]')
        counts = check_contacts(args[0])
        bad = fixture_contacts(counts) if fixture else []
        emit('contacts', counts)
        if bad:
            raise SystemExit('fixture mismatch ' + ','.join(bad))
        return 0
    if cmd == 'build-messages':
        if len(args) != 2:
            raise SystemExit('usage: build-messages SRC DST [--fixture]')
        counts = build_messages(args[0], args[1])
        bad = fixture_messages(counts) if fixture else []
        emit('messages', counts)
        if bad:
            raise SystemExit('fixture mismatch ' + ','.join(bad))
        return 0
    if cmd == 'snapshot':
        if len(args) != 2:
            raise SystemExit('usage: snapshot SRC DST')
        emit('snapshot', snapshot(args[0], args[1]))
        return 0
    raise SystemExit('unknown command')


if __name__ == '__main__':
    try:
        code = main(sys.argv[1:])
    except SystemExit as err:
        if err.code not in (0, None):
            sys.stderr.write(str(err.code or 'failed') + '\n')
            sys.exit(1)
        sys.exit(0)
    except Exception as err:
        sys.stderr.write(safe_error(err) + '\n')
        sys.exit(1)
    sys.exit(code)
