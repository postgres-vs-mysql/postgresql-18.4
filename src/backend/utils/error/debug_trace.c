#include "debug_trace.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <semaphore.h>

#define TRACE_SEM_NAME "/trace_output_lock"

sem_t *trace_sem = NULL;
int trace_fp = 0;
static __thread TraceContext *thread_ctx = NULL;
time_t last_sec = -1;
int  last_sec_processed_logs = 0;
int  trace_process_slow_mode = 0;
struct tm *last_tm;
char trace_buffer[65536];
int  trace_buffer_pos = 0;
int trace_disabled = 0;
int trace_thead_mode = 0;
extern int max_trace_iterations;
extern int min_trace_iterations;

__attribute__((constructor))
static void init_trace_lock()
{
  trace_sem = sem_open(TRACE_SEM_NAME, O_CREAT, 0666, 1);

  if (trace_sem == SEM_FAILED) {
    perror("sem_open");
    exit(EXIT_FAILURE);
  }

  trace_fp = open("trace.log", O_WRONLY | O_CREAT | O_APPEND, 0644);

  if (trace_fp < 0) {
    perror("fopen trace.log");
    exit(EXIT_FAILURE);
  }
}

__attribute__((destructor))
static void cleanup_trace_lock()
{
  if (trace_fp >= 0) {
    close(trace_fp);
    trace_fp = -1;
  }

  if (trace_sem != SEM_FAILED && trace_sem != NULL) {
    sem_close(trace_sem);
  }
}

bool is_trace_enabled(void)
{
  if (trace_disabled == 0) {
    return true;
  } else {
    return false;
  }
}

bool is_trace_thread_mode(void)
{
  if (trace_thead_mode == 1) {
    return true;
  } else {
    return false;
  }
}

int retrieve_max_trace_iterations(void) {
  return max_trace_iterations;
}

int retrieve_min_trace_iterations(void) {
  return min_trace_iterations;
}

int test_for_rust(void) {
  return 0;
}

int test_for_rust2(void) {
  return 0;
}

void set_trace_enabled(void)
{
  trace_disabled = 0;
}

void set_trace_disabled(void)
{
  trace_disabled = 1;
}

void set_trace_thread_mode(void)
{
  trace_thead_mode = 1;
}

void set_trace_process_mode(void)
{
  trace_thead_mode = 0;
}

void rust_trace_function_enter(const char *function, size_t len)
{
  DBUG_TRACE_FUNC_ENTER(function, len);
}

void rust_trace_function_exit(const char *function, size_t len)
{
  DBUG_TRACE_FUNC_EXIT(function, len);
}

void rust_trace_print(const char *fmt, ...)
{
  char buf[256];
  va_list args;

  if (fmt == NULL) {
    return;
  }

  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  if (!trace_thead_mode) {
    DBUG_PRINT("rust", "%s", buf);
  } else {
    DBUG_PRINT_FOR_THREAD("rust", "%s", buf);
  }
}

void rust_trace_instant_print(const char *fmt, ...)
{
  char buf[256];
  va_list args;

  if (fmt == NULL) {
    return;
  }

  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  if (!trace_thead_mode) {
    DBUG_INSTANT_PRINT("rust", "%s", buf);
  } else {
    DBUG_PRINT_FOR_THREAD("rust", "%s", buf);
  }
}

void set_trace_ctx_null(void)
{
  if (thread_ctx) {
    free(thread_ctx);
  }

  thread_ctx = NULL;
}

TraceContext *get_trace_ctx(void)
{
  if (!thread_ctx) {
    thread_ctx = calloc(1, sizeof(TraceContext));

    trace_thead_mode = 0;
    if (!thread_ctx) {
      perror("calloc");
      exit(EXIT_FAILURE);
    }
  }

  return thread_ctx;
}

void trace_lock(void)
{
  if (sem_wait(trace_sem) != 0) {
    perror("sem_wait");
  }
}

void trace_unlock(void)
{
  if (sem_post(trace_sem) != 0) {
    perror("sem_post");
  }
}


