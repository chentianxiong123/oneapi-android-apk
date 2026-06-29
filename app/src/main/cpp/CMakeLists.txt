cmake_minimum_required(VERSION 3.18)
project(dns_hook C)
add_library(dns_hook SHARED dns_hook.c)
target_link_libraries(dns_hook dl)