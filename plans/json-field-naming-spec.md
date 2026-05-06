# json-field-naming-spec.md

Status: spec

JSON instances in `common/` are derived via `DerivingVia` using `deriving-aeson`.

1. **Records**: Use `PrefixedSnake "prefix"` to strip internal Haskell prefixes.
2. **Sum Types**: Prefix constructors (e.g., `PhaseGreen`) to avoid collisions, then use `PrefixedSnake "prefix"` to strip them in JSON.

Example:
```haskell
import Deriving.Aeson.Stock

data PeriodPhase = PeriodPhaseGreen | PeriodPhaseYellow | PeriodPhaseRed
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "PeriodPhase" PeriodPhase

data PeriodStatusResponse = PeriodStatusResponse
  { psrPhase :: PeriodPhase
  ...
  }
  deriving stock (Eq, Show, Generic)
  deriving (FromJSON, ToJSON) via PrefixedSnake "psr" PeriodStatusResponse
```
