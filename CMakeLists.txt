cmake_minimum_required(VERSION 3.24)
project(ToraLibtorrentAdapter LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(ToraLibtorrentAdapter
    Sources/ToraLibtorrentBridge/LibtorrentSession.cpp
    Sources/ToraLibtorrentBridge/ToraLibtorrentBridge.mm
)

set(TORA_LIBTORRENT_PREFIX "" CACHE PATH "Path to libtorrent-rasterbar prefix")
set(TORA_BOOST_PREFIX "" CACHE PATH "Path to Boost prefix")

target_include_directories(ToraLibtorrentAdapter
    PUBLIC
        Sources/ToraLibtorrentBridge/include
        Sources/ToraLibtorrentBridge
)

if(TORA_LIBTORRENT_PREFIX)
    target_include_directories(ToraLibtorrentAdapter PRIVATE "${TORA_LIBTORRENT_PREFIX}/include")
    target_link_directories(ToraLibtorrentAdapter PRIVATE "${TORA_LIBTORRENT_PREFIX}/lib")
    target_link_libraries(ToraLibtorrentAdapter PRIVATE torrent-rasterbar)
endif()

if(TORA_BOOST_PREFIX)
    target_include_directories(ToraLibtorrentAdapter PRIVATE "${TORA_BOOST_PREFIX}/include")
    target_link_directories(ToraLibtorrentAdapter PRIVATE "${TORA_BOOST_PREFIX}/lib")
endif()
