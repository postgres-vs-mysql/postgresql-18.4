#include "debug_trace.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
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

void set_trace_enabled(void)
{
  trace_disabled = 0;
}

void set_trace_disabled(void)
{
  trace_disabled = 1;
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


