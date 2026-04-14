// Copyright (c) 2023-present The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or https://opensource.org/license/mit/.
//
// This file provides build configuration for Bitcoin Core libbitcoinkernel
// when built with Swift Package Manager. It replaces the CMake-generated
// bitcoin-build-config.h with platform-appropriate values.

#ifndef BITCOIN_CONFIG_H
#define BITCOIN_CONFIG_H

/* Version Build */
#define CLIENT_VERSION_BUILD 0

/* Version is release */
#define CLIENT_VERSION_IS_RELEASE true

/* Major version */
#define CLIENT_VERSION_MAJOR 31

/* Minor version */
#define CLIENT_VERSION_MINOR 0

/* Copyright holder(s) before %s replacement */
#define COPYRIGHT_HOLDERS "The %s developers"

/* Copyright holder(s) */
#define COPYRIGHT_HOLDERS_FINAL "The Bitcoin Core developers"

/* Replacement for %s in copyright holders string */
#define COPYRIGHT_HOLDERS_SUBSTITUTION "Bitcoin Core"

/* Copyright year */
#define COPYRIGHT_YEAR 2026

/* Define to 1 if you have the declaration of `fork', and to 0 if you don't. */
#define HAVE_DECL_FORK 1

/* Define to 1 if you have the declaration of `pipe2', and to 0 if you don't. */
#define HAVE_DECL_PIPE2 0

/* Define to 1 if you have the declaration of `setsid', and to 0 if you don't. */
#define HAVE_DECL_SETSID 1

/* Define to 1 if fdatasync is available. */
/* #undef HAVE_FDATASYNC */

/* Define this symbol if the BSD getentropy system call is available with
   sys/random.h (macOS only; iOS does not ship sys/random.h) */
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#define HAVE_GETENTROPY_RAND 1
#endif

/* Define to 1 if O_CLOEXEC flag is available. */
#define HAVE_O_CLOEXEC 1

/* Define this symbol if platform supports unix domain sockets */
#define HAVE_SOCKADDR_UN 1

/* Define this symbol if the BSD sysctl() is available */
#define HAVE_SYSCTL 1

/* Define to 1 if std::system or ::wsystem is available.
   system() is unavailable on iOS. */
#if TARGET_OS_OSX
#define HAVE_SYSTEM 1
#endif

/* Define to the address where bug reports for this package should be sent. */
#define CLIENT_BUGREPORT "https://github.com/bitcoin/bitcoin/issues"

/* Define to the full name of this package. */
#define CLIENT_NAME "Bitcoin Core"

/* Define to the home page for this package. */
#define CLIENT_URL "https://bitcoincore.org/"

/* Define to the version of this package. */
#define CLIENT_VERSION_STRING "31.0.0"

/* Define to 1 if strerror_r returns char *. */
/* #undef STRERROR_R_CHAR_P */

/* Export kernel API symbols when building the library */
#define BITCOINKERNEL_BUILD 1

#endif //BITCOIN_CONFIG_H
