#!/bin/bash

if [ -e $LBPLOG/weather4lox/current.json ]; then
	cp $LBPLOG/weather4lox/current.json $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/dailyforecast.json ]; then
	cp $LBPLOG/weather4lox/dailyforecast.json $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/hourlyforecast.json ]; then
	cp $LBPLOG/weather4lox/hourlyforecast.json $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/webpage.html ]; then
	cp $LBPLOG/weather4lox/webpage.html $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/webpage.map.html ]; then
	cp $LBPLOG/weather4lox/webpage.map.html $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/webpage.dfc.html ]; then
	cp $LBPLOG/weather4lox/webpage.dfc.html $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/webpage.hfc.html ]; then
	cp $LBPLOG/weather4lox/webpage.hfc.html $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/weatherdata.html ]; then
	cp $LBPLOG/weather4lox/weatherdata.html $LBPDATA/weather4lox
fi
if [ -e $LBPLOG/weather4lox/index.txt ]; then
	cp $LBPLOG/weather4lox/index.txt $LBPDATA/weather4lox
fi
