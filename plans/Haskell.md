# Haskell.md

- All packages use **relude** as the custom prelude
- Default extensions across all packages: DataKinds, DerivingStrategies, OverloadedStrings, StrictData, TypeFamilies, ViewPatterns, LambdaCase, MultiWayIf, DerivingVia, NoImplicitPrelude
- all imports are explicit via import lists, except for `import Relude`

## cabal stanza requirements

Every `library` and `executable` stanza must declare `default-language: Haskell2010`. Without it, Cabal silently skips `default-extensions`, producing errors like `illegal lambda-case expression: use LambdaCase` even though the extension is listed. Place it right after `hs-source-dirs:`.