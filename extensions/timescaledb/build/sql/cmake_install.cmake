# Install script for directory: /home/wangbin/work/timescaledb/sql

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/usr/local")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "0")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

# Set path to fallback-tool for dependency-resolution.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/opt/rh/devtoolset-11/root/usr/bin/objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/wangbin/pgsql_trace/share/extension/timescaledb--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.26.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.26.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.26.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.26.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.25.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.25.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.25.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.24.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.23.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.23.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.22.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.22.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.21.4--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.21.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.21.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.21.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.21.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.20.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.20.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.20.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.20.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.19.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.19.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.19.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.19.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.18.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.18.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.18.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.17.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.17.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.17.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.16.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.16.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.15.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.15.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.15.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.15.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.14.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.14.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.14.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.13.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.13.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.12.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.12.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.12.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.11.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.11.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.11.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.10.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.10.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.10.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.10.0--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.9.3--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.9.2--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.9.1--2.27.0-dev.sql;/home/wangbin/pgsql_trace/share/extension/timescaledb--2.9.0--2.27.0-dev.sql")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/wangbin/pgsql_trace/share/extension" TYPE FILE FILES
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.26.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.26.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.26.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.26.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.25.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.25.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.25.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.24.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.23.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.23.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.22.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.22.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.21.4--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.21.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.21.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.21.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.21.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.20.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.20.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.20.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.20.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.19.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.19.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.19.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.19.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.18.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.18.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.18.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.17.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.17.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.17.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.16.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.16.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.15.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.15.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.15.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.15.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.14.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.14.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.14.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.13.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.13.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.12.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.12.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.12.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.11.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.11.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.11.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.10.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.10.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.10.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.10.0--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.9.3--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.9.2--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.9.1--2.27.0-dev.sql"
    "/home/wangbin/work/timescaledb/build/sql/timescaledb--2.9.0--2.27.0-dev.sql"
    )
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/home/wangbin/work/timescaledb/build/sql/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
