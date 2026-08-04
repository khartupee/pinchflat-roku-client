#!/bin/bash
# Connect to Roku telnet using the IP from .env (same as deploy.sh)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/.env"
telnet "$ROKU_IP" 8085 
