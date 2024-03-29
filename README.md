# help.nix

A small Nix library for adding something akin to `--help` to your `default.nix` files using `nix-build -A help`.

The easiest way to get started is with `withHelp`:

```nix
{ pkgs ? import <nixpkgs> {} }:
let
  helpLib = pkgs.callPackage ./. {};
in helpLib.withHelp (self: help: {
  hello = help "This builds the hello package" pkgs.hello;
})
```

With this you can run `nix-build -A hello` to build `hello` or `nix-build -A help` to see all the help messages.

## Usage

### `withHelpConfig`

Adds help documentation to an attrset used for nix-build/nix-shell (often in default.nix).

```haskell
withHelp :: AttrSet -> (AttrSet -> (String -> Any -> Any) -> AttrSet) -> AttrSet
```

Given an attrset annotated with help information, `withHelpConfig` will return an attrset with all annotations erased and up to two additional attributes:
  * `help`: An attribute that throws an error describing all the documented targets
  * `all`: An attribute that returns the original, unannotated attrset for use in building
           all targets at once.

Example:

```nix
let x = withHelpConfig {} (self: help: {
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

`self` is a reference to the unannotated attrset that will be returned by `withHelpConfig`. You must use this instead of `rec { ... }`
since built-in recursive attrsets will not strip off the annotations.

### `withHelp`

Like `withHelpConfig` but using the default configuration:
  * `help` is the name of the attribute for throwing the help message.
  * `all` is the name of the attribute for building all attributes.
  * A default header message is provided.
