//
//  Header.h
//  
//
//  Created by csjones on 5/28/24.
//

#ifndef bitcoind_h
#define bitcoind_h

// Declare the entry function that exists in the C++ code
int entry(int argc, char* argv[]);

// Request a graceful shutdown of the daemon
void StartShutdown();

#endif /* bitcoind_h */
