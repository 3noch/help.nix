{ lib, ... }:
let
  inherit (lib) concatStrings concatStringsSep filterAttrs mapAttrs mapAttrsToList nameValuePair;
in rec {
  # Internally used functions: they are exported here under 'internal' because they can
  # come in handy for users who want more advanced usage.
  internal = rec {
    # Like lib.isAttrs but masks errors with a result of 'false'.
    isAttrs = x: let result = builtins.tryEval (lib.isAttrs x); in result.success && result.value;
    # Like lib.isDerivation but masks errors with a result of 'false'.
    isDerivation = x: let result = builtins.tryEval (lib.isDerivation x); in result.success && result.value;

    # Like lib.mapAttrsRecursiveCond but decides if a node is an attribute set
    # *after* applying f, instead of before. This a allows 'f' to affect recursion depth.
    # For original implementation see: https://github.com/NixOS/nixpkgs/blob/3cb1b521bfb52ca94e9c804e5f984c95483c2b36/lib/attrsets.nix#L519
    #
    # : (Any -> Bool) -> (Any -> Any) -> Attrset -> AttrSet
    mapAttrsNestedRecursiveCond = cond: f: set:
      let
        recurse = path: set:
          let
            g = name: value:
              let value' = f (path ++ [name]) value; in
              if isAttrs value' && cond value
                then recurse (path ++ [name]) value'
                else value';
          in mapAttrs g set;
      in recurse [] set;

    # Annotates an arbitrary value 'x' with a help message.
    # The result is always an attrset that has __orig, __help, and __shallow attrs.
    #   * __orig stores the unaltered 'x'.
    #   * __help stores the help message string for 'x'.
    #   * __shallow is true/false and defaults to false. When true, it forces help traversal to stop.
    #
    # : a -> Annotated a
    annotate = msg: x: { __orig = x; __help = msg; __shallow = false; };

    # Like annotate but sets the shallow bit.
    # : a -> Annotated a
    shallowAnnotate = msg: x: annotate msg x // { __shallow = true; };

    # Returns true when the given value matches the structure of an annotated attrset.
    # : Any -> Bool
    hasHelp = x: isAttrs x && x ? __orig && x ? __help;

    # Recursively strips help annotations by rebuilding a structure of only original values.
    # : Annotated a -> a
    eraseHelp = mapAttrsNestedRecursiveCond (_: true) (_name: value: if hasHelp value then value.__orig else value);

    # Builds the a list of entries that should be included in the output of 'help'.
    # The resulting list of AttrSets has these keys:
    #   * path : List String is a path to the attribute key from the root (names of keys are list elements)
    #   * help : Maybe String is either null (no help) or a String of the help message.
    #   * value : Any is the original value.
    #
    # : AttrSet -> AttrSet -> List { path : List String, help : String, value : Any }
    buildHelpEntries = { annotatedAttrsOnly ? true, basePath ? [], shouldSkip ? isDerivation, ... }:
      let
        recurse = path: as:
          let
            next = if !hasHelp as then as else if as.__shallow then {} else as.__orig;
            nextAttrs = if !(isAttrs next) then {} else filterAttrs (_name: hasHelp) next; # We will recurse into these.
            unannotatedAttrs = if annotatedAttrsOnly || !(isAttrs next) || shouldSkip next # We will list these if requested.
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

    # A default function for rendering the help line of a particular help entry in an AttrSet.
    # See buildHelpEntries for documentation of the meaning of each key in the input AttrSet.
    #
    # : { path, help, value } -> String
    defaultRenderEntry = { path, help, value }:
      let
        dottedPath = concatStringsSep "." path;
      in if isAttrs value && !(isDerivation value) then ["${dottedPath}: (attrset) ${if help == null then "" else help}"]
        else ["${dottedPath}${if help == null then "" else " - ${help}"}"];

    # A default ordering function between two help entries.
    # This orders entries with null help after entries with help.
    #
    # : { path, help, value } -> { path, help, value } -> Bool
    defaultComparison = x: y:
      let
        asStr = { path, help, ... }: "${if help == null then "1" else "0"}${concatStrings path}";
      in asStr x < asStr y;

    # Builds the final help String from a list of entries.
    #
    # : AttrSet -> List { path, help, value } -> String
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
  # Given an attrset annotated with help information, `withHelpConfig` will return an attrset with
  # all annotations erased and up to two additional attributes:
  #   * help: An attribute that throws an error describing all the documented targets
  #   * all: An attribute that returns the original, unannotated attrset for use in building
  #          all targets at once.
  #
  # Example:
  #     let x = withHelpConfig {} (self: help: {
  #       package = help "This is a package" pkg;
  #       packageAlias = help "DEPRECATED: Use package instead" self.package;
  #
  #       subset = help "Sub-targets" {
  #         helper = help "A helper utility" helperPkg;
  #       };
  #     })
  #
  # Evaluating `x.help` produces:
  #   error: Help:
  #
  #   The following targets are documented:
  #
  #   package - This is a package
  #   packageAlias - DEPRECATED: Use package instead
  #
  #   subset: Sub-targets
  #   subset.helper - A helper utility
  #
  # And evaluating `x.subset.helper` builds the `helperPkg`.
  #
  # Here `help` is a function that annotates an attribute with a string.
  # If you annotate an attrset that itself contains more annotated attrsets,
  # the documentation will recurse.
  #
  # `self` is a reference to the unannotated attrset that will be returned
  # by `withHelpConfig`. You must use this instead of `rec { ... }` since
  # built-in recursive attrsets will not strip off the annotations.
  #
  # : AttrSet -> (AttrSet -> (String -> Any -> Any) -> AttrSet) -> AttrSet
  withHelpConfig =
    { annotate ? internal.annotate
    , helpAttribute ? "help"
    , wrapper ? (docs: "Help:\n\nThe following targets are available:\n\n" + docs)
    , throw ? builtins.throw
    , allAttribute ? "all"
    # annotatedAttrsOnly ? true
    , ...
    }@config: mkAttrs:
    let
      attrs = mkAttrs self annotate;
      self = internal.eraseHelp attrs;
    in self // {
      ${helpAttribute} = throw (wrapper (internal.buildHelp config attrs));
      ${allAttribute} = self;
    };

  # Like `withHelpConfig` but using the default configuration:
  #   `help` is the name of the attribute for throwing the help message.
  #   `all` is the name of the attribute for building all attributes.
  #   A default header message is provided.
  withHelp = withHelpConfig {};

  # Wraps each attribute in an attrset with help annotations when the keys match.
  #
  # For example:
  #     zipHelp help { a = 1; b = 2;} { a = "A One"; b = "A Two"; }
  #
  #   is equivalent to
  #
  #     { a = help "A One" 1; b = help "A Two" 2; }
  zipHelp = help: orig: annots:
    mapAttrs (name: value: if annots ? ${name} then help annots.${name} value else value) orig;
}
