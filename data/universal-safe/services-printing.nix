/*
  Personal printer data for `kdn.services.printing`.

  This file is a module, not a data value. It assigns options that
  `modules/universal/services/printing/default.nix` declares, so that module holds no printer
  name, no device URI and no location.

  The body reads no module argument, so the file is a plain attribute set with no function head.
  nixpkgs `lib/modules.nix` accepts both forms.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file, `printers` falls back to `[ ]`, and `defaultPrinter` falls back to `null`.

  The two options exist in every context. Only the NixOS branch of the module reads them, so
  this file needs no context guard. A darwin host sets `kdn.services.printing.enable = true`
  through the desktop profile and still writes no `hardware.printers` definition.
*/
{
  config.kdn.services.printing.defaultPrinter = "HP-M110w-home";
  config.kdn.services.printing.printers = [
    {
      name = "HP-M110w-home";
      location = "Home";
      deviceUri = "ipp://192.168.41.25";
      model = "drv:///hp/hpcups.drv/hp-laserjet_m109-m112.ppd";
      ppdOptions.PageSize = "A4";
    }
  ];
}
