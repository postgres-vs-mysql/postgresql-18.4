#ifndef DEBUG_TRACE_H
#define DEBUG_TRACE_H

#include <stdio.h>
#include <pthread.h>
#include <time.h>
#include <sys/time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <string.h>

#define MAX_STACK_DEPTH 128
#define MAX_COL_LEN 2048
#define MAX_DBUG_BUF_LEN 16384
#define TRACE_LOG_FAST_LIMIT 8192
#define EXPECTED_TOP 2
#define MAX_RUST_FUNC_LEN 120

typedef struct {
  const char *func;
  char rust_func[MAX_RUST_FUNC_LEN];
} TraceFrame;

typedef struct {
  TraceFrame stack[MAX_STACK_DEPTH];
  int top;
} TraceContext;


TraceContext *get_trace_ctx(void);
void set_trace_ctx_null(void);
void trace_lock(void);
void trace_unlock(void);
void set_trace_enabled(void);
void set_trace_disabled(void);

extern int trace_disabled;

extern int trace_fp;
extern int trace_process_slow_mode;
extern int last_sec_processed_logs;
extern time_t last_sec;
extern struct tm *last_tm;
extern char trace_buffer[];
extern int  trace_buffer_pos;


static inline int u32_to_str(unsigned int value, char *buffer, int min_width) {
  char temp[10];
  int i = 0;
  int pad, pos, j;

  if (value == 0) {
    temp[i++] = '0';
  } else {
    while (value > 0) {
      temp[i++] = '0' + (value % 10);
      value /= 10;
    }
  }

  pad = (min_width > i) ? (min_width - i) : 0;
  pos = 0;

  for (j = 0; j < pad; ++j) {
    buffer[pos++] = '0';
  }


  for (j = i - 1; j >= 0; --j) {
    buffer[pos++] = temp[j];
  }

  buffer[pos] = '\0';
  return pos;
}

static inline void trace_info(unsigned int pid, int depth, const char *func, int enter) {
  char *buf = trace_buffer + trace_buffer_pos;
  int pos =0;
  int len =0;
  int i;
  int func_len;
  int tm_hour, tm_min, tm_sec;
  struct timeval tv;
  gettimeofday(&tv, NULL);
  if (tv.tv_sec != last_sec) {
    last_sec = tv.tv_sec;
    last_tm = localtime(&tv.tv_sec);
    if (last_sec_processed_logs > 0 && last_sec_processed_logs < TRACE_LOG_FAST_LIMIT) {
      trace_process_slow_mode = 1;
    } else {
      trace_process_slow_mode = 0;
    }
    last_sec_processed_logs = 0;
  }
  tm_hour = last_tm->tm_hour;
  tm_min = last_tm->tm_min;
  tm_sec = last_tm->tm_sec;

  len = u32_to_str(tm_hour, buf + pos, 2);
  pos = pos + len;
  buf[pos++] = ':';
  len = u32_to_str(tm_min, buf + pos, 2);
  pos = pos + len;
  buf[pos++] = ':';
  len = u32_to_str(tm_sec, buf + pos, 2);
  pos = pos + len;
  buf[pos++] = '.';
  len = u32_to_str(tv.tv_usec, buf + pos, 6);
  pos = pos + len;
  buf[pos++] = ' ';

  buf[pos++] = 'P';
  buf[pos++] = '@';
  len = u32_to_str(pid, buf + pos, 1);
  pos = pos + len;
  buf[pos++] = '@';
  len = u32_to_str(depth, buf + pos, 2);
  pos = pos + len;
  buf[pos++] = ' ';

  if (depth > MAX_STACK_DEPTH) {
     fprintf(stderr, "depth is too high:%d\n", depth);
  }
  for (i = 0; i < depth; ++i) {
    buf[pos++] = '|';
  }

  if (func) {
    func_len = (int) strlen(func);
    if (enter) {
      buf[pos++] = '>';
    } else {
      buf[pos++] = '<';
    }
    for (i = 0; i < func_len; ++i) {
      buf[pos++] = func[i];
    }

    buf[pos++] = ' ';
    buf[pos++] = '[';
    buf[pos++] = 'x';
    buf[pos++] = 'm';
    buf[pos++] = 'l';
    buf[pos++] = '2';
    buf[pos++] = ']';
    buf[pos++] = '\n';
  }

  trace_buffer_pos += pos;
}

#define DBUG_PRINT(keyword, msg, ...) \
  do { \
    __attribute__((unused)) ssize_t _ign; \
    TraceContext *trace_ctx = get_trace_ctx(); \
    int trace_written = 0; \
    if (trace_disabled) break;  \
    if (trace_ctx->top >= MAX_STACK_DEPTH || trace_ctx->top < 0) { \
        break; \
    } \
    trace_info(getpid(), trace_ctx->top, NULL, 0); \
    last_sec_processed_logs++; \
    if (sizeof((char[]){#__VA_ARGS__}) > 1) {  \
      trace_written = snprintf(trace_buffer + trace_buffer_pos, MAX_COL_LEN, "%s: " msg "\n", keyword, ##__VA_ARGS__); \
    } else { \
      trace_written = snprintf(trace_buffer + trace_buffer_pos, MAX_COL_LEN, "%s: %s\n", keyword, msg); \
    } \
    if (trace_written >= MAX_COL_LEN) { \
       trace_buffer_pos += (MAX_COL_LEN - 1); \
       trace_buffer[trace_buffer_pos - 1] = '\n'; \
    } else { \
       trace_buffer_pos += trace_written; \
    } \
    if (trace_buffer_pos > MAX_DBUG_BUF_LEN || trace_process_slow_mode) { \
      trace_lock(); \
      _ign = write(trace_fp, trace_buffer, trace_buffer_pos); \
      trace_unlock(); \
      trace_buffer_pos = 0; \
    } \
  } while (0)

#define DBUG_INSTANT_PRINT(keyword, msg, ...) \
  do { \
    TraceContext *trace_ctx = get_trace_ctx(); \
    __attribute__((unused)) ssize_t _ign; \
    int trace_written = 0; \
    if (trace_disabled) break;  \
    if (trace_ctx->top >= MAX_STACK_DEPTH || trace_ctx->top < 0) { \
        break; \
    } \
    trace_info(getpid(), trace_ctx->top, NULL, 0); \
    last_sec_processed_logs++; \
    if (sizeof((char[]){#__VA_ARGS__}) > 1) {  \
      trace_written = snprintf(trace_buffer + trace_buffer_pos, MAX_COL_LEN, "%s: " msg "\n", keyword, ##__VA_ARGS__); \
    } else { \
      trace_written = snprintf(trace_buffer + trace_buffer_pos, MAX_COL_LEN, "%s: %s\n", keyword, msg); \
    } \
    if (trace_written >= MAX_COL_LEN) { \
       trace_buffer_pos += (MAX_COL_LEN - 1); \
       trace_buffer[trace_buffer_pos - 1] = '\n'; \
    } else { \
       trace_buffer_pos += trace_written; \
    } \
    trace_lock(); \
    _ign = write(trace_fp, trace_buffer, trace_buffer_pos); \
    trace_unlock(); \
    trace_buffer_pos = 0; \
  } while (0)


typedef struct {
  const char *func;
  int level;
} dbug_trace_t;

static inline dbug_trace_t dbug_special_trace_enter(const char *func) {
  __attribute__((unused)) ssize_t _ign;
  TraceContext *ctx = get_trace_ctx();
  if (trace_disabled) return (dbug_trace_t){func, -1};
  if (ctx->top > MAX_STACK_DEPTH || ctx->top < 0) {
     return (dbug_trace_t){func, - 1};
  }
  if (ctx->top != EXPECTED_TOP) {
      ctx->top = EXPECTED_TOP;
  } 
  trace_info(getpid(), ctx->top, func, 1); 
  last_sec_processed_logs++;
  if (trace_buffer_pos > MAX_DBUG_BUF_LEN) {
    trace_buffer[trace_buffer_pos] = '\0';
    trace_lock();
    _ign = write(trace_fp, trace_buffer, trace_buffer_pos);
    trace_unlock();
    trace_buffer_pos = 0;
  }
  ctx->stack[ctx->top++].func = func;
  return (dbug_trace_t){func, ctx->top - 1};
}

static inline dbug_trace_t dbug_trace_enter(const char *func) {
  __attribute__((unused)) ssize_t _ign;
  TraceContext *ctx = get_trace_ctx();
  if (trace_disabled) return (dbug_trace_t){func, -1};

  if (ctx->top >= MAX_STACK_DEPTH || ctx->top < 0) {
     return (dbug_trace_t){func, - 1};
  }
  trace_info(getpid(), ctx->top, func, 1); 
  last_sec_processed_logs++;
  if (trace_buffer_pos > MAX_DBUG_BUF_LEN) {
    trace_buffer[trace_buffer_pos] = '\0';
    trace_lock();
    _ign = write(trace_fp, trace_buffer, trace_buffer_pos);
    trace_unlock();
    trace_buffer_pos = 0;
  }
  ctx->stack[ctx->top++].func = func;
  return (dbug_trace_t){func, ctx->top - 1};
}

static inline void dbug_trace_exit(dbug_trace_t *t) {
  __attribute__((unused)) ssize_t _ign;
  TraceContext *ctx = get_trace_ctx();
  if (trace_disabled)  return;
  if (ctx->top > MAX_STACK_DEPTH || ctx->top < 0) {
     fprintf(stderr, "exit, depth is too high:%d\n", ctx->top);
     return;
  }
  if (ctx->top == t->level + 1) {
    const char *func = ctx->stack[--ctx->top].func;
    trace_info(getpid(), ctx->top, func, 0); 
    last_sec_processed_logs++;
    if (trace_buffer_pos > MAX_DBUG_BUF_LEN) {
      trace_buffer[trace_buffer_pos] = '\0';
      trace_lock();
      _ign = write(trace_fp, trace_buffer, trace_buffer_pos);
      trace_unlock();
      trace_buffer_pos = 0;
    }
  } else {
    const char *error = "stack error\n";
    trace_lock();
    _ign = write(trace_fp, error, strlen(error));
    trace_unlock();
  }
}

#define DBUG_TRACE \
  dbug_trace_t __trace_guard__ __attribute__((__cleanup__(dbug_trace_exit))) = dbug_trace_enter(__func__)

#define DBUG_ADJUST_TRACE \
  dbug_trace_t __trace_guard__ __attribute__((__cleanup__(dbug_trace_exit))) = dbug_special_trace_enter(__func__)

#endif // DEBUG_TRACE_H

