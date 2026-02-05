{lib}: let
  parseSopsYAMLMetadata = file: let
    collectPaths = entries: let
      collector = state: cur: let
        curResult = {
          inherit (cur) type;
          path = map (p: p.key) parents;
        };
        update =
          if cur.type != null && (builtins.head parents).key != "sops"
          then {result = state.result ++ [curResult];}
          else {inherit parents;};

        parents = builtins.filter (p: p.indent < cur.indent) state.parents ++ [cur];
      in
        state // update;

      initialState = {
        parents = [(builtins.head entries)];
        result = [];
      };
      endState = lib.lists.foldl collector initialState (builtins.tail entries);
    in
      endState.result;
  in
    lib.pipe file [
      (file: lib.trivial.throwIfNot (lib.strings.hasSuffix ".sops.yaml" file) "Can only parse '*.sops.yaml' files!" file)
      builtins.readFile
      (lib.strings.splitString "\n")
      (map (line: let
        match = builtins.match "^([[:space:]]*)([^:]+):[[:space:]]?(ENC\\[.*type:([^,]+)?.*])?$" line;
      in
        lib.lists.optional (match != null) {
          indent = builtins.stringLength (builtins.elemAt match 0);
          key = builtins.elemAt match 1;
          value = builtins.elemAt match 2;
          type = builtins.elemAt match 3;
        }))
      builtins.concatLists
      collectPaths
    ];
in {
  inherit parseSopsYAMLMetadata;
}
