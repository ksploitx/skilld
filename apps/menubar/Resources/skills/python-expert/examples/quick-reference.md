# Python Expert — Quick Reference

## Cheatsheet: common patterns

### Pathlib
```python
from pathlib import Path
p = Path.home() / ".claude" / "skills"
p.mkdir(parents=True, exist_ok=True)
content = (p / "SKILL.md").read_text()
```

### Dataclass with slots
```python
from dataclasses import dataclass

@dataclass(slots=True, frozen=True)
class Skill:
    name: str
    description: str
    folder: str
```

### Type-narrowing
```python
from typing import assert_never

def handle(x: int | str) -> str:
    match x:
        case int(): return str(x)
        case str(): return x
        case _ as unreachable:
            assert_never(unreachable)
```
