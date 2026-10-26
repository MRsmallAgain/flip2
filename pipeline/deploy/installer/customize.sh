ui_print " "
ui_print "flip2 installer (@FLAVOR@ flavor)"
ui_print "Installs on first boot; see /cache/flip2-installer.log"
ui_print "De-root helper: /data/local/flip2/deroot.sh"
ui_print " "
set_perm_recursive "$MODPATH/payload" 0 0 0755 0644
set_perm "$MODPATH/payload/deroot.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
