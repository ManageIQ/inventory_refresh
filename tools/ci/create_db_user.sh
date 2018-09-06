#!/bin/bash

psql -c "CREATE USER root SUPERUSER PASSWORD 'smartvm';" -U postgres
