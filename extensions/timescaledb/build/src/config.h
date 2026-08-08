#ifndef TIMESCALEDB_CONFIG_H
#define TIMESCALEDB_CONFIG_H

#define TIMESCALEDB_VERSION "2.27.0"
#define TIMESCALEDB_VERSION_MOD "2.27.0-dev"
#define TIMESCALEDB_MAJOR_VERSION "2"
#define TIMESCALEDB_MINOR_VERSION "27"
#define TIMESCALEDB_PATCH_VERSION "0"
#define TIMESCALEDB_MOD_VERSION "dev"
#define BUILD_OS_NAME "Linux"
#define BUILD_OS_VERSION "6.6.87.2-microsoft-standard-WSL2"
#define BUILD_PROCESSOR "x86_64"
#define BUILD_POINTER_BYTES 8

/*
 * Value should be set in package release scripts. Otherwise
 * defaults to "source"
 */
#define TIMESCALEDB_INSTALL_METHOD "source"

/* Platform */
#ifndef WIN32
/* #undef WIN32 */
#endif
#ifndef MSVC
/* #undef MSVC */
#endif
#ifndef UNIX
#define UNIX
#endif
#ifndef APPLE
/* #undef APPLE */
#endif

#ifndef DEBUG
/* #undef DEBUG */
#endif

#ifndef TS_DEBUG
/* #undef TS_DEBUG */
#endif

#ifndef USE_TELEMETRY
#define USE_TELEMETRY
#endif

#ifndef TELEMETRY_DEFAULT
#define TELEMETRY_DEFAULT TELEMETRY_BASIC
#endif

/* Avoid conflicts with USE_OPENSSL defined by PostgreSQL */
/* #undef TS_USE_OPENSSL */

#endif /* TIMESCALEDB_CONFIG_H */
