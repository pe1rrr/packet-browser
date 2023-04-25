## Usage & Installation
Prerequisits:

```
sudo apt install lynx
sudo apt install openbsd-inetd
```

Add the following line to /etc/inetd.conf
 
```
 browse		stream	tcp	nowait	bpq		/full/path/to/your/packet-browser/browse.sh client ax25
```

The word ``bpq`` above refers to the userid that this process will run under, if using a Raspberry Pi, the default is ``pi`` so keep that in mind.

Add the following line to ``/etc/services`` and make a note of the port number you choose. Make sure the one you pick does not exist and is within the range of ports available.

```
 browse		63004/tcp   # Browser
```
 
Enable inetd: 
```
sudo systemctl enable inetd
sudo service inetd start
```

In ``bpq32.cfg`` add the port specified above (63004) to the BPQ Telnet port list, ``CMDPORT=``

Note the port's position offset in the list as that will be referenced in the ``APPLICATION`` line next.

The first port in the ``CMDPORT=`` line is position 0 (zero), the next would be 1, then 2 and so on.

Locate your ``APPLICATION`` line definitions in ``bpq32.cfg`` and another one next in the sequence. Make sure it has a unique <app number> between 1-32.

Syntax: 
```
 APPLICATION <app number 1-32>,<node command>,<node instruction>

 APPLICATION 25,WEB,C 10 HOST 1 S

```
 ``<node instruction>`` is where the command 'web' is told to use BPQ port 10 (the telnet port, yours may be different!)

``HOST`` is a command to tell BPQ to look at the BPQ Telnet ``CMDPORT=`` list, and '1' is to pick offset position 1, that in turn resolves to TCP port 63004. The 'S' tells the node to return the user back to the node when they exit the web portal instead of disconnecting them, it refers to the word 'Stay'.

## OpenDNS Family Shield Protection

If you want to protect your system using DNS filtering then it is advisable to set up ``squid`` proxy, however this is beyond the scope of this document, but it involves using ``squid`` to proxy traffic using DNS serviers conifgured for it rather than the host system's DNS resolver. 

If you do not want to use DNS filtering using services such as OpenDNS Family Shield to block users from requesting explicit content then comment out the proxy settings:

```
myproxy="http://127.0.0.1:3128"
export http_proxy=$myproxy
export https_proxy=$myproxy
```
