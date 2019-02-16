#!/bin/bash
go run main.go master distributed data*.txt
sort -n -k2 mrtmp.wcseq | tail -100
rm mrtmp.wcseq*
rm worker*