```mermaid
flowchart TD
    A[Start] --> B[Do Something]
    B --> C{Decision}
    C -->|Yes| D[Finish]
    C -->|No| E[Retry]
    E --> B
```
