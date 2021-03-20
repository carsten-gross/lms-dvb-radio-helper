# lms-dvb-radio-helper
The radio-list.pl script creates an automatic, dynamic favorites list for
accessing the radio programs available in tvheadend. Most likely you also want
to install and use ts2shout to listen to the radio programs with EPG or RDS
information.

The idea is to add the CGI URL of this script to the Squeezebox "Favorites".
For Apache I have already prepared a suitable configuration section for a
Debian installation. The prepared configuration is set up to call
http://localhost/station/ directly. This call directly generates an overview of
all channel-tags.

A description of the setup is stored on
http://www.siski.de/~carsten/tvheadend.html.

Activate modules (if not already done) mod_cgi and mod_action (a2enmod cgi ;
a2enmod action) on your apache2.  Take care that radio-list.pl is placed in the
cgi-bin of the webserver, on debian it is searched in /usr/lib/cgi-bin. Be careful
with permissions and reachability - the script is not intended for world-wide reachability.

At the beginning of radio-list.pl some individual parameters have to be
configured (among others hostname, username and password for tvheadend access).

The file 000-default.conf is a configuration template for apache2 which can be
used instead of the file stored in Debian. 

Please adjust the IP addresses in the apache configuration file. 
