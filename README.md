# help.nix

## `withHelp'`

Adds help documentation to an attrset used for nix-build/nix-shell (often in default.nix).

```haskell
withHelp' :: AttrSet -> ((String -> Any -> Any) -> AttrSet -> AttrSet) -> AttrSet
```

Given an attrset annotated with help information, `withHelp'` will return an attrset with all annotations erased and up to two additional attributes:
  * help: An attribute that throws an error describing all the documented targets
  * all: An attribute that returns the original, unannotated attrset for use in building
         all targets at once.

Example:

```nix
let x = withHelp' {} (help: self: {
  package = help "This is a package" pkg;
  packageAlias = help "DEPRECATED: Use package instead" self.package;

  subset = help "Sub-targets" {
    helper = help "A helper utility" helperPkg;
  };
})
```

Evaluating `x.help` produces:
```
error: Help:

The following targets are documented:

package - This is a package
packageAlias - DEPRECATED: Use package instead

subset: Sub-targets
subset.helper - A helper utility
```

And evaluating `x.subset.helper` builds the `helperPkg`.

Here `help` is a function that annotates an attribute with a string. If you annotate an attrset that itself contains more annotated attrsets, the documentation will recurse.

`self` is a reference to the unannotated attrset that will be returned by `withHelp'`. You must use this instead of `rec { ... }`
since built-in recursive attrsets will not strip off the annotations.

## `withHelp`

Like `withHelp'` but using the default configuration:
  * `help` is the name of the attribute for throwing the help message.
  * `all` is the name of the attribute for building all attributes.
  * A default header message is provided.
