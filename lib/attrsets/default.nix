# adapted from https://stackoverflow.com/a/54505212
{ lib, ... }:
let
  /*
    Merges list of records, concatenates arrays, if two values can't be merged - the latter is preferred

    Example 1:
    recursiveMerge [
      { a = "x"; c = "m"; list = [1]; }
      { a = "y"; b = "z"; list = [2]; }
    ]

    returns

    { a = "y"; b = "z"; c="m"; list = [1 2] }

    Example 2:
    recursiveMerge [
      {
        a.a = [1];
        a.b = 1;
        a.c = [1 1];
        boot.loader.grub.enable = true;
        boot.loader.grub.device = "/dev/hda";
      }
      {
        a.a = [2];
        a.b = 2;
        a.c = [1 2];
        boot.loader.grub.device = "";
      }
    ]

    returns

    {
      a = {
        a = [ 1 2 ];
        b = 2;
        c = [ 1 2 ];
      };
      boot = {
        loader = {
          grub = {
            device = "";
            enable = true;
          };
        };
      };
    }
  */
  recursiveMerge =
    attrList:
    let
      f =
        attrPath:
        lib.zipAttrsWith (
          n: values:
          if lib.tail values == [ ] then
            lib.head values
          else if lib.all lib.isList values then
            lib.unique (lib.concatLists values)
          else if lib.all lib.isAttrs values then
            f (attrPath ++ [ n ]) values
          else
            lib.last values
        );
    in
    f [ ] attrList;
in
{
  inherit recursiveMerge;
}
