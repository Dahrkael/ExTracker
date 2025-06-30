![ExTracker](.github/extracker-logo.png)
The Bittorrent Tracker made in Elixir

[![CI](https://github.com/Dahrkael/ExTracker/actions/workflows/build-on-push.yml/badge.svg)](https://github.com/Dahrkael/ExTracker/actions/workflows/build-on-push.yml)
[![CI](https://github.com/Dahrkael/ExTracker/actions/workflows/test-on-push.yml/badge.svg)](https://github.com/Dahrkael/ExTracker/actions/workflows/test-on-push.yml)
[![CI](https://github.com/Dahrkael/ExTracker/actions/workflows/docker-release.yml/badge.svg)](https://github.com/Dahrkael/ExTracker/actions/workflows/docker-release.yml)

👷‍♂️This project is a Work In Progress. While not ready for full industrial usage it does work.  
There is a testing instance running at [extracker.dahrkael.net:6969](http://extracker.dahrkael.net:6969/about) with all current features enabled ([Live statistics](http://extracker.dahrkael.net:9568/tracker-stats.html)).

## Features
Implementation Legend: 
🔲 Not Yet 🔰 Partially ✅ Done ❌ Won't do

### Important Features
- ✅ High performance (uses ALL the available cores, in-memory storage)
- ✅ Low memory usage (~200MB of RAM for each 1.000.000 peers)
- ✅ Zero setup (launch it and it just works)

### Tracker-related BitTorrent Enhancement Proposals

#### Final and Active Process BEPs
- ✅ **BEP 0:** [The BitTorrent Protocol Specification](https://www.bittorrent.org/beps/bep_0003.html)
#### Accepted BEPs
- ✅ **BEP 15:** [UDP Tracker Protocol](https://www.bittorrent.org/beps/bep_0015.html)
- ✅ **BEP 23:** [Tracker Returns Compact Peer Lists](https://www.bittorrent.org/beps/bep_0023.html)
- 🔲 **BEP 27:** [Private Torrents](https://www.bittorrent.org/beps/bep_0027.html)
#### Draft BEPs
- ✅ **BEP 7:** [IPv6 Tracker Extension](https://www.bittorrent.org/beps/bep_0007.html)
- ✅ **BEP 21:** [Extension for partial seeds](https://www.bittorrent.org/beps/bep_0021.html)
- ✅ **BEP 24:** [Tracker Returns External IP](https://www.bittorrent.org/beps/bep_0024.html)
- 🔲 **BEP 31:** [Tracker Failure Retry Extension](https://www.bittorrent.org/beps/bep_0031.html)
- ✅ **BEP 41:** [UDP Tracker Protocol Extensions](https://www.bittorrent.org/beps/bep_0041.html)
- ✅ **BEP 48:** [Tracker Protocol Extension: Scrape](https://www.bittorrent.org/beps/bep_0048.html)
- ✅ **BEP 52:** [The BitTorrent Protocol Specification v2](https://www.bittorrent.org/beps/bep_0052.html)
#### Deferred BEPs
- ❌ **BEP 8:** [Tracker Peer Obfuscation](https://www.bittorrent.org/beps/bep_0008.html)

### Other Features
- ✅ HTTPS support
- ✅ Database backups to disk
- ❌ WebTorrent
- 🔰 Infohash whitelist/blacklist
- 🔰 Peer management (interval enforcement, cleanup, banning, etc)
- 🔰 Metrics
- 🔰 GeoIP support (statistics, peer restrictions)
- **Feel free to propose features in the [Issues](https://github.com/Dahrkael/ExTracker/issues)**

## Setup
There are 3 main ways of running ExTracker currently

### Straight from source code
For this method to work you need to have **Erlang** and **Elixir** installed on your system
- Clone the repository: `git clone https://github.com/Dahrkael/ExTracker.git && cd ExTracker`
- If needed, modify the configuration in [config/runtime.exs](https://github.com/Dahrkael/ExTracker/blob/master/config/runtime.exs) to fit your needs
- run `MIX_ENV=prod iex -S mix`

### From Releases
Currently there are no official releases built (soon™️). You can however make your own and deploy it where needed:
- Clone the repository: `git clone https://github.com/Dahrkael/ExTracker.git && cd ExTracker`
- run `MIX_ENV=prod mix release extracker` for Linux or `MIX_ENV=prod mix release extrackerw` for Windows
- Find the release files inside the *_build/prod/rel/extracker* folder (if its a different machine make sure the OS and architecture is the same!)
- Copy the folder to its final destination
- If needed, modify the configuration in [releases/{VERSION}/runtime.exs](https://github.com/Dahrkael/ExTracker/blob/master/config/runtime.exs) to fit your needs
- Run `bin/extracker start`

### Docker
For this method you can directly run the [available docker image](https://github.com/Dahrkael/ExTracker/pkgs/container/extracker/422008654?tag=latest): `docker run ghcr.io/dahrkael/extracker:latest`  
or use it as part of docker-compose. Theres an [example compose file](https://github.com/Dahrkael/ExTracker/blob/master/docker-compose.yml) available.

> [!NOTE]
> Since modifying the [runtime.exs](https://github.com/Dahrkael/ExTracker/blob/master/config/runtime.exs) file to tune the configuration inside the container is not easy you can also configure it using **Environment Variables**, see the example compose file for the complete list.

## Copyright and license

Copyright (c) Dahrkael \<dahrkael at outlook dot com\>  
Distributed under the terms of the Apache License, Version 2.0. Please refer to the [LICENSE file](https://github.com/Dahrkael/ExTracker/blob/master/LICENSE) in the repository root directory for details.
