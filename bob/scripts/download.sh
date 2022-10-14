#!/bin/sh

# {"version": "1.2.89", "sha1": "5ca3dd134cc960c35ecefe12f6dc81a48f212d40"}
SHA1=$(curl -s http://d.defold.com/stable/info.json | sed 's/.*sha1": "\(.*\)".*/\1/')
echo "Using Defold dmengine_headless version ${SHA1}"

#DMENGINE_URL="http://d.defold.com/archive/${SHA1}/engine/linux/dmengine_headless"
DMENGINE_URL="http://d.defold.com/archive/stable/${SHA1}/engine/${PLATFORM}/dmengine_headless"
BOB_URL="http://d.defold.com/archive/stable/${SHA1}/bob/bob.jar"

# download bob.jar
curl -L -o /usr/local/bin/bob.jar http://d.defold.com/archive/${SHA1}/bob/bob.jar

# download dmengine_headless
curl -L -o /usr/local/bin/dmengine_headless http://d.defold.com/archive/${SHA1}/engine/x86_64-linux/dmengine_headless \
    && chmod +x /usr/local/bin/dmengine_headless
