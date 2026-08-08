# PostgreSQL Trace Logging Guide

This guide explains how to use the trace logging features added to this PostgreSQL project. These logs are designed to help you understand what PostgreSQL is doing internally. They are great for learning, debugging, and exploring.

> Join our [Discord server](https://discord.gg/g8ksTXPPnY) to discuss PostgreSQL and MySQL with other database enthusiasts.

---

## General Guidelines

### 1. Avoid tracing inside signal handlers

Trace logging should not be performed within signal handlers, as doing so may induce latch-related deadlocks.

---

### 2. Know how log output works

| Output Method      | Behavior                                                                                                           |
|:------------------ |:------------------------------------------------------------------------------------------------------------------ |
| DBUG_PRINT         | Writes log but does not flush to disk immediately. This is designed for efficient trace logging.                   |
| DBUG_INSTANT_PRINT | Flushes immediately. This is useful for abnormal debugging or when invoked at the end of SQL statement processing. |

---

### 3. Use parameters to control repeated log output

- max_trace_iterations
- min_trace_iterations

Due to the heavy use of function pointers in PostgreSQL, the same interface may be called multiple times internally. However, the actual function being invoked can differ each time, which may affect the accuracy of the trace results.
Increase these values if you need more detailed logs for in-depth analysis.

---

### 4. Autovacuum trace is off by default

To avoid excessive autovacuum-related log output, autovacuum tracing is disabled by default.
Turn it on only when needed:

```sql
SET enable_autovacuum_trace = on;
```

---

### 5. Recommended: Session-Level Tracing

This mode minimizes overhead during data loading and records traces only for the SQL statements you want to analyze.

First, disable global tracing in the PostgreSQL configuration file:

```text
enable_global_trace = off
enable_session_trace = off
enable_autovacuum_trace = off
```

Then, when you're ready to analyze a query, enable tracing for the current session:

```sql
SET enable_session_trace = on;
```

> **Note:** Session-level tracing applies only to the current session. If you connect to another database (for example, by running `\c new_database` in `psql`), you'll need to enable it again.

---

### 6. Coverage is broad but not complete

Tracing covers most core areas, but not every module or edge case.
If you hit a scenario that isn't logged, feel free to add your own trace logs!

---

### 7. AI-assisted log analysis

If the trace logs are not too large for the AI's context limit, you can feed them to an AI assistant to help interpret internal flows. Always double-check the AI's output, as it may contain errors.

---

### 8. Contribute new tracing use cases

Found a great scenario that should be traced? Please open a GitHub issue. We would love to improve coverage together!

---

### 9. Extensions directory

Commonly used extensions are located in this directory. We have added trace logging support for these extensions to help with debugging and understanding their internal behavior.

---

### 10. Trace Examples

Through tracing PostgreSQL and MySQL, we have produced the following in-depth content:

1. [PostgreSQL Uncovered: Internals, Trace Analysis, and Performance](https://wangbin579.gumroad.com/l/postgresql_course)

2. [MySQL Uncovered: Internals, Trace Analysis, and Performance](https://wangbin579.gumroad.com/l/mysql_course)

---

## License

This project is released under the PostgreSQL License.
All trace-related modifications and additions follow the same terms.
