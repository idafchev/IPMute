# IPMute
Powershell script to block communication from processes by utilizing secondary IP addresses for sinkholing

1. Edit the script and define which processes to monitor/block  
2. Execute and let it run. For any discovered TCP connection coming from the monitored processes, the remote IP will be added as a secondary IP address to the network interface, effectively sinkholing that traffic to the local adapter.  
3. CTRL+C will initiate cleanup and terminate

The script is of POC quality and makes changes to the network configuration of the host. You may cut out your internet connection :) 
