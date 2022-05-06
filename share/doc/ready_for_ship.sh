#!/bin/bash

# This prepares the example channel for shipping after possibly being used
# for testing.  Testing makes log and database files appear which don't really
# need to be on github.

rm example-channel.tar.gz
rm -rf example-channel.dist
rm -vf example-channel/logs/*.txt
rm -vf example-channel/database/*.db
cp -dpRv example-channel/ example-channel.dist
tar cvzf example-channel.tar.gz example-channel/ example-channel.dist/ 

