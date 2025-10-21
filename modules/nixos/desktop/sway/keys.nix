# Mapping of Sway config modifiers to understandable names
/*
  from `man 5 sway`:

      bindsym [--whole-window] [--border] [--exclude-titlebar] [--release] [--locked] [--to-code] [--input-device=<device>] [--no-warn] [--no-repeat] [--inhibited] [Group<1-4>+]<key combo> <command>
          Binds key combo to execute the sway command command when pressed. You may use XKB key names here (wev(1) is a good tool for discovering these). With the flag --release, the command is executed when the key combo is released. If input-device is given, the binding will only be executed for that input device and will be executed instead of any  binding  that  is
          generic to all devices. If a group number is given, then the binding will only be available for that group. By default, if you overwrite a binding, swaynag will give you a warning. To silence this, use the --no-warn flag.

          For specifying modifier keys, you can use the XKB modifier names Shift, Lock (for Caps Lock), Control, Mod1 (for Alt), Mod2 (for Num Lock), Mod3 (for XKB modifier Mod3), Mod4 (for the Logo key), and Mod5 (for AltGr). In addition, you can use the aliases  Ctrl (for Control), Alt (for Alt), and Super (for the Logo key).

          Unless  the  flag  --locked is set, the command will not be run when a screen locking program is active. If there is a matching binding with and without --locked, the one with will be preferred when locked and the one without will be preferred when unlocked. If there are matching bindings and one has both --input-device and --locked and the other has neither,
          the former will be preferred even when unlocked.

          Unless the flag --inhibited is set, the command will not be run when a keyboard shortcuts inhibitor is active for the currently focused window. Such inhibitors are usually requested by remote desktop and virtualisation software to enable the user to send keyboard shortcuts to the remote or virtual session. The --inhibited flag allows one  to  define  bindings
          which will be exempt from pass-through to such software. The same preference logic as for --locked applies.

          Unless the flag --no-repeat is set, the command will be run repeatedly when the key is held, according to the repeat settings specified in the input configuration.

          Bindings to keysyms are layout-dependent. This can be changed with the --to-code flag. In this case, the keysyms will be translated into the corresponding keycodes in the first configured layout.

          Mouse  bindings  operate  on  the  container  under the cursor instead of the container that has focus. Mouse buttons can either be specified in the form button[1-9] or by using the name of the event code (ex BTN_LEFT or BTN_RIGHT). For the former option, the buttons will be mapped to their values in X11 (1=left, 2=middle, 3=right, 4=scroll up, 5=scroll down,
          6=scroll left, 7=scroll right, 8=back, 9=forward). For the latter option, you can find the event names using libinput debug-events.

          The priority for matching bindings is as follows: input device, group, and locked state.

          --whole-window, --border, and --exclude-titlebar are mouse-only options which affect the region in which the mouse bindings can be triggered.  By default, mouse bindings are only triggered when over the title bar. With the --border option, the border of the window will be included in this region. With the --whole-window option, the cursor can be anywhere over
          a window including the title, border, and content. --exclude-titlebar can be used in conjunction with any other option to specify that the titlebar should be excluded from the region of consideration.

          If --whole-window is given, the command can be triggered when the cursor is over an empty workspace. Using a mouse binding over a layer surface's exclusive region is not currently possible.

          Example:
                    # Execute firefox when alt, shift, and f are pressed together
                    bindsym Mod1+Shift+f exec firefox

          bindcode [--whole-window] [--border] [--exclude-titlebar] [--release] [--locked] [--input-device=<device>] [--no-warn] [--no-repeat] [--inhibited] [Group<1-4>+]<code> <command> is also available for binding with key/button codes instead of key/button names.
*/
{
  alt = "Alt";
  caps-lock = "lock";
  ctrl = "Control";
  delete = "Delete";
  lalt = "Mod1";
  modifier = "Mod3";
  mouse-down = "Button4";
  mouse-up = "Button5";
  num-lock = "Mod2";
  ralt = "Mod5";
  shift = "Shift";
  super = "Super";
  superMod = "Mod4";
}
