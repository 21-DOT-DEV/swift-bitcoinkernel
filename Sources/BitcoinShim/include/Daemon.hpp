//
//  Daemon.hpp
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

#ifndef Daemon_hpp
#define Daemon_hpp

#include <stdio.h>

#ifdef __cplusplus
extern "C"
{
#endif

int daemon_init(int argc, char* argv[]);

#ifdef __cplusplus
}
#endif

#endif /* Daemon_hpp */
