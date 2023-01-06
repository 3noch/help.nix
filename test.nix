{ pkgs ? import <nixpkgs> {} }:
let
  helpPkg = pkgs.callPackage ./. {};

  # Configure our help output to be very simple and just return the string instead of throwing.
  getHelp = config: f: (helpPkg.withHelpConfig ({ throw = x: x;  wrapper = x: x; } // config) f).help;

  results = pkgs.lib.runTests {
    testSimpleHelp = {
      expr = getHelp {} (self: help: {
        hasHelp1 = help "This has help" 1;
        hasHelp2 = help "This has help too" 2;
      });
      expected = "hasHelp1 - This has help\nhasHelp2 - This has help too";
    };

    testWrappingError = {
      expr = getHelp {} (self: help: {
        goesBoom = help "This goes boom" (throw "boom");
      });
      expected = "goesBoom - This goes boom";
    };

    testWrappingDrv = {
      expr = getHelp {} (self: help: {
        hello = help "hello pkg" pkgs.hello;
      });
      expected = "hello - hello pkg";
    };

    testNested = {
      expr = getHelp {} (self: help: {
        parent = help "Parent" {
          child = help "Child" {
            grandchild = help "Grandchild" 1;
          };
        };
      });
      expected = ''
        parent: (attrset) Parent
        parent.child: (attrset) Child
        parent.child.grandchild - Grandchild'';
    };

    testNestingStopsNonAnnotated = {
      expr = getHelp {} (self: help: {
        parent = help "Parent" {
          child = {
            grandchild = help "Grandchild" 1;
          };
        };
      });
      expected = "parent: (attrset) Parent";
    };

    testIgnoringNonAnnotated = {
      expr = getHelp {} (self: help: {
        noHelp1 = 1;
        noHelp2 = 2;
      });
      expected = "";
    };

    testShowingNonAnnotated = {
      expr = getHelp { annotatedAttrsOnly = false; } (self: help: {
        noHelp1 = 1;
        noHelp2 = 2;
      });
      expected = "noHelp1\nnoHelp2";
    };

    testGettingAnnotatedValue = {
      expr = (helpPkg.withHelp (self: help: {
        hasHelp1 = help "This has help" 1;
        hasHelp2 = help "This also has help" 2;
      })).hasHelp1;
      expected = 1;
    };

    testGettingNestedAnnotatedValue = {
      expr = (helpPkg.withHelp (self: help: {
        parent = help "Parent" {
          child = help "Child" {
            grandchild = help "Grandchild" 1;
          };
        };
      })).parent.child.grandchild;
      expected = 1;
    };

    testGettingAnnotatedValueWithSelf = {
      expr = (helpPkg.withHelp (self: help: {
        hasHelp1 = help "This has help" 1;
        hasHelp2 = help "This also has help" self.hasHelp1;
      })).hasHelp1;
      expected = 1;
    };

    testGettingNonAnnotatedValue = {
      expr = (helpPkg.withHelp (self: help: {
        noHelp1 = 1;
        noHelp2 = 2;
      })).noHelp2;
      expected = 2;
    };

    testZipHelp = {
      expr = getHelp {} (self: help: helpPkg.zipHelp help {
        a = 1;
        b = 2;
      } {
        a = "A";
        b = "B";
      });
      expected = "a - A\nb - B";
    };
  };
in helpPkg.withHelp (self: help: {
  hello = help "The hello package" pkgs.hello;
  tests = help "Run tests" (if builtins.length results == 0 then [] else throw (builtins.toJSON results));
})
