{ lib, ... }:
let
  inherit (lib) concatStrings concatStringsSep filterAttrs mapAttrs mapAttrsToList nameValuePair;
in rec {
  internal = rec {
    isAttrs = x: let result = builtins.tryEval (lib.isAttrs x); in result.success && result.value;
    isDerivation = x: let result = builtins.tryEval (lib.isDerivation x); in result.success && result.value;

    mapAttrsNestedRecursiveCond = pred: f: set:
      let
        recurse = path: set:
          let
            g = name: value:
              let value' = f (path ++ [name]) value; in
              if pred value && isAttrs value'
                then recurse (path ++ [name]) value'
                else value';
          in mapAttrs g set;
      in recurse [] set;

    annotate = msg: x: { __orig = x; __help = msg; __shallow = false; };
    shallowAnnotate = msg: x: annotate msg x // { __shallow = true; };
    hasHelp = x: isAttrs x && x ? __orig && x ? __help;
    eraseHelp = mapAttrsNestedRecursiveCond (_: true) (_name: value: if hasHelp value then value.__orig else value);
    buildHelpEntries = { basePath ? [], annotatedAttrsOnly ? true, neverKeep ? isDerivation, ... }:
      let
        recurse = path: as:
          let
            next = if !(hasHelp as) then as else if as.__shallow then {} else as.__orig;
            nextAttrs = if !(isAttrs next) then {} else filterAttrs (_name: hasHelp) next; # We will recurse into these.
            unannotatedAttrs = if annotatedAttrsOnly || !(isAttrs next) || neverKeep next # We will list these if requested.
              then {}
              else filterAttrs (_name: value: !(hasHelp value)) next;
            entry =
              if hasHelp as then [{ inherit path; help = as.__help; value = as.__orig; }]
              else [];
          in entry
            ++
            builtins.concatLists (
              mapAttrsToList (name: value: recurse (path ++ [name]) value) nextAttrs
            )
            ++
            mapAttrsToList (name: value: { path = path ++ [name]; help = null; inherit value; }) unannotatedAttrs
            ;
      in recurse basePath;
    defaultRenderEntry = { path, help, value }:
      let
        dottedPath = concatStringsSep "." path;
      in if isAttrs value && !(isDerivation value) then ["${dottedPath}: (attrset) ${if help == null then "" else help}"]
        else ["${dottedPath}${if help == null then "" else " - ${help}"}"];
    defaultComparison = x: y:
      let
        asStr = { path, help, ... }: "${if help == null then "1" else "0"}${concatStrings path}";
      in asStr x < asStr y;
    buildHelp =
      { prepareEntries ? builtins.sort defaultComparison
      , renderEntry ? defaultRenderEntry
      , additionalEntries ? []
      , ...
      }@config: as: concatStringsSep "\n" (
        builtins.concatMap renderEntry (
          prepareEntries (buildHelpEntries config as ++ additionalEntries)
        )
    );
  };

  # Adds help documentation to an attrset used for nix-build/nix-shell (often in default.nix).
  #
  # withHelp' :: AttrSet -> ((String -> Any -> Any) -> AttrSet -> AttrSet) -> AttrSet
  #
  # Given an attrset annotated with help information, `withHelp'` will return an attrset with
  # all annotations erased and up to two additional attributes:
  #    * help: An attribute that throws an error describing all the documented targets
  #    * all: An attribute that returns the original, unannotated attrset for use in building
  #           all targets at once.
  #
  # Example:
  #     let x = withHelp' {} (help: self: {
  #       package = help "This is a package" pkg;
  #       packageAlias = help "DEPRECATED: Use package instead" self.package;
  #
  #       subset = help "Sub-targets" {
  #         helper = help "A helper utility" helperPkg;
  #       };
  #     })
  #
  #  Evaluating `x.help` produces:
  #    error: Help:
  #
  #    The following targets are documented:
  #
  #    package - This is a package
  #    packageAlias - DEPRECATED: Use package instead
  #
  #    subset: Sub-targets
  #    subset.helper - A helper utility
  #
  #  And evaluating `x.subset.helper` builds the `helperPkg`.
  #
  #  Here `help` is a function that annotates an attribute with a string.
  #  If you annotate an attrset that itself contains more annotated attrsets,
  #  the documentation will recurse.
  #
  #  `self` is a reference to the unannotated attrset that will be returned
  #  by `withHelp'`. You must use this instead of `rec { ... }` since built-in
  #  recursive attrsets will not strip off the annotations.
  withHelp' =
    { annotate ? internal.annotate
    , helpAttribute ? "help"
    , wrapper ? (docs: "Help:\n\nThe following targets are available:\n\n" + docs)
    , throw ? builtins.throw
    , allAttribute ? "all"
    , ...
    }@config: mkAttrs:
    let
      attrs = mkAttrs annotate self;
      self = internal.eraseHelp attrs;
    in self // {
      ${helpAttribute} = throw (wrapper (internal.buildHelp config attrs));
      ${allAttribute} = self;
    };

  # Like `withHelp'` but using the default configuration:
  #   `help` is the name of the attribute for throwing the help message.
  #   `all` is the name of the attribute for building all attributes.
  #   A default header message is provided.
  withHelp = withHelp' {};

  # Wraps each attribute in an attrset with help annotations when the keys match.
  #
  # For example:
  #     wrapHelp help { a = 1; b = 2;} { a = "A One"; b = "A Two"; }
  #
  #   is equivalent to
  #
  #     { a = help "A One" 1; b = help "A Two" 2; }
  wrapHelp = help: orig: annots: mapAttrs (name: value: if annots ? ${name} then help annots.${name} value else value) orig;
}
