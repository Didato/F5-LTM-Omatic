# F5-LTM-Omatic :  "Elastic F5 Automation"
# F5 LTM Automation for Services Deployment and Management. 
# This Code is in Ruby and requires a Tranport to send JSON Formated Messages, These are parsed and executed.  You will want to read the RunBook to understand the usage.  
# I reccomend using and AMQ, Puppet or NRPE agent for Command Parser, but anyting will work.  Community supported API for Ruby may be better choice. 
# Author: Chris Didato
# chrisdidato@gmail.com
# Git: https://github.com/Didato
# Linked In: https://www.linkedin.com/in/chrisdidato
# 
#
#Load Balancer Config Module v13.rc1 ()
########################################### 
# Example parameters: 
# { /standard headers/, 
#     parameters:{ 
#     "user":"bigpimpin",
#     "host":"f5host", 
#     "ip":"192.168.12.14"
#     "port : 8080"
#     "vlan : 2001"
#     "poolname : pool_123"
#     "ipnet : /24" # Bits
#     "vsname : VirtualServer1"  #VS Name usually has a corrosoponding Desinsation IP as the Virtaul Address
#     "vlanname : App123_LB_Internal"
#     "interfacenumber : 1.2"
#     "source-addr : 192.168.12.122"
#     "timeout : 15"  #seconds    
#     "mask : 255.255.255.0" #octet 
#     "pr_cookie : Cookie_NAME" # Pick a Cookie name like My_First_Cooking
#     "expiration : 2:0:0:0" # this is set for 2 Days:  Formmat = D:H:M:S
#     "monitorname : MY_HTTP "  #  Put in your own name for a custom monitor. 
#     "recv : "Service is Alive" "
#     "geturl : GET /index.html\r\n" : recv "Server [1-3]"  OR GET www.yahoo.com/index.html : recv "Service is Alive"
#     "pr_srcname : MY_PR_SOURCE_NAME"  # name for Source Value
#      }
# }
###########################################

# USAGE () 
# {
# echo "Usage: $0 directive poolname ip port "
# echo "Directives = { add-pool | add-member | remove-members | delete-pool |
# remove-members | delete-pool | create-vlan | create-net-self |
# create-netself-allowservice | create-vs | create-persistence-rule 
# | add-persistence-to-vs | create-cookie | map-cookie-to-vs |create-hc"
# echo "See Run Book for details"  
# }
############################################


require 'net/ssh'
require 'ipaddr'


class LB_Command_Error < StandardError
  attr :error_code
  def initialize(error_code)
    @error_code = error_code
  end
end
class F5_command_error < LB_Command_Error
end

class AMQAgentCommandProcessor
## The AMQAgentCommandProcessor is an agent that takeS in JSON Formated Paramaters.    You will need your own as I do not provie this.  
##
# Common ssh Method
def f5_command(message, command)
   begin
     Net::SSH.start(message.parameters.fetch("host"), message.parameters.fetch("user"), :password => message.parameters.fetch("password")) do |ssh|
       ##
       # Things to do in the ssh session
       # log.debug hangs, use 'puts' instead
       cmdLogStr = "Executing command: #{command}"
       puts cmdLogStr
        ssh.exec!(command) do |ch, stream, data|
         @log.debug("Received LB response: #{data}")
          if stream == :stderr
            @log.info("Error: #{data}")
            raise LB_Command_Error.new(3)
          else
            output=data
          end
        print ssh.exec!("exit")
       end  # ssh session
     end # Net::SSH connection
   rescue LB_Command_Error
     @log.info("Command error!")
     message.create_fail_msg("Command failure")
     raise
   end
end # Common ssh Method





# Create Container "LPTC"
# sample parameters:
#	PodName:	pod1.prod
#	ContainerName:	LPTC
#	MajorVLAN:	101
#	MinorVLAN:	2011
#	MinorAddrBlk:	192.168.4.240/28
#
# sample commands. Note that all the nodes are created whether they exist or not.  That way, the load balancer is setup once initially and does
#   not need to be changed when hosts are added or removed from a container by the Configurator.
#   FIXME: the size of the container is currently hard-coded at 11 rather than passed as a parameter
# create /net vlan VLAN2011 tag 2011 interfaces add { LAG1 { tagged } }
# create /net route-domain RD2011 id 2011 parent RD101 strict enabled vlans add { VLAN2011 }
# create /net self /pod1.prod/SelfIP-LB1-2011 address 192.168.4.242%2011/28 vlan VLAN2011 traffic-group traffic-group-local-only
# create /net self /pod1.prod/SelfIP-LB-2011 address 192.168.4.241%2011/28 vlan VLAN2011 traffic-group traffic-group-1
# create /ltm snat /pod1.prod/VLAN2011-Out origins add { 192.168.4.240%2011/28 { } } translation VLAN101-Out vlans-enabled vlans add { VLAN2011 } description "LPTC Container"
# create /ltm node /pod1.prod/LPTC001 address 192.168.4.244%2011
# create /ltm node /pod1.prod/LPTC002 address 192.168.4.245%2011
# create /ltm node /pod1.prod/LPTC003 address 192.168.4.246%2011
# create /ltm node /pod1.prod/LPTC004 address 192.168.4.247%2011 
# create /ltm node /pod1.prod/LPTC005 address 192.168.4.248%2011
# create /ltm node /pod1.prod/LPTC006 address 192.168.4.249%2011
# create /ltm node /pod1.prod/LPTC007 address 192.168.4.250%2011
# create /ltm node /pod1.prod/LPTC008 address 192.168.4.251%2011
# create /ltm node /pod1.prod/LPTC009 address 192.168.4.252%2011
# create /ltm node /pod1.prod/LPTC010 address 192.168.4.253%2011
# create /ltm node /pod1.prod/LPTC011 address 192.168.4.254%2011
# 
  def create_container(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_container command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    
    case parameters.fetch("lb_type")
          when "f5" then 
               podName = parameters.fetch('PodName')
               containerName = parameters.fetch('ContainerName')
               majorVLAN = parameters.fetch('MajorVLAN')
               minorVLAN = parameters.fetch('MinorVLAN') 
               minorAddrBlk = parameters.fetch('MinorAddrBlk')
               ipaddr = IPAddr.new(minorAddrBlk)
               ipaddr1 = ipaddr.succ()
               ipaddr2 = ipaddr1.succ()
               start_node_ipaddr = ipaddr2.succ().succ()
               mask = minorAddrBlk.split('/', 2)[1]
                        
               @log.info("PodName is #{podName}")              
               @log.info("ContainerName is #{containerName}")             
               @log.info("MajorVLAN is #{majorVLAN}")             
               @log.info("MinorVLAN is #{minorVLAN}")               
               @log.info("MinorAddrBlk is #{minorAddrBlk}")                             
               @log.info("self ip 1 is #{ipaddr1.to_s}")              
               @log.info("self ip 2 is #{ipaddr2.to_s}")             
               @log.info("self ip 4 is #{start_node_ipaddr.to_s}") 
               @log.info("mask is #{mask}")    

               # log.info hangs after being passed the thirdF5Msg as input, so use plain 'puts'for this output instead 
               firstF5Msg = "tmsh create /net vlan VLAN#{minorVLAN} tag #{minorVLAN} interfaces add \173 LAG1 \173 tagged \175 \175"  
               puts firstF5Msg                     
               f5_command(message, firstF5Msg)
               secondF5Msg = "tmsh create /net route-domain RD#{minorVLAN} id #{minorVLAN} parent RD#{majorVLAN} strict enabled vlans add { VLAN#{minorVLAN} }"
               puts secondF5Msg        
               f5_command(message, secondF5Msg)
               thirdF5Msg = "tmsh create /net self /#{podName}/SelfIP-LB1-#{minorVLAN} address #{ipaddr2.to_s}\045#{minorVLAN}/#{mask} vlan VLAN#{minorVLAN} traffic-group traffic-group-local-only"
               puts thirdF5Msg   
               f5_command(message, thirdF5Msg)
               fourthF5Msg = "tmsh create /net self /#{podName}/SelfIP-LB-#{minorVLAN} address #{ipaddr1.to_s}\045#{minorVLAN}/#{mask} vlan VLAN#{minorVLAN} traffic-group traffic-group-1"
               puts fourthF5Msg      
               f5_command(message, fourthF5Msg)
               fifthF5Msg = "tmsh create /ltm snat /#{podName}/VLAN#{minorVLAN}-Out origins add { #{ipaddr.to_s}\045#{minorVLAN}/#{mask} { } } translation VLAN#{majorVLAN}-Out vlans-enabled vlans add { VLAN#{minorVLAN} } description \"#{containerName} Container\""
               puts fifthF5Msg            
               f5_command(message, fifthF5Msg)
               for i in 1..11
                 suffix = "%03d" %[i]
                 nextF5Msg = "tmsh create /ltm node /#{podName}/#{containerName}#{suffix} address #{start_node_ipaddr.to_s}\045#{minorVLAN}"
                 puts nextF5Msg
                 f5_command(message, nextF5Msg)
                 start_node_ipaddr = start_node_ipaddr.succ()
               end
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_container

# to remove a container, issue the 'delete' equivalent of the 'create' commands in the 'create_container' function, but in reverse order
  def remove_container(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_container command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    
    case parameters.fetch("lb_type")
          when "f5" then 
               podName = parameters.fetch('PodName')
               containerName = parameters.fetch('ContainerName')
               minorVLAN = parameters.fetch('MinorVLAN') 
                     
               @log.info("PodName is #{podName}")              
               @log.info("ContainerName is #{containerName}")                                     
               @log.info("MinorVLAN is #{minorVLAN}")               
              
               # log.info hangs on some messages so use plain 'puts' instead               
               for i in 1..11
                 suffix = "%03d" %[i]
                 nextF5Msg = "tmsh delete /ltm node /#{podName}/#{containerName}#{suffix} "
                 puts nextF5Msg
                 f5_command(message, nextF5Msg)
               end
               firstF5Msg = "tmsh delete /ltm snat /#{podName}/VLAN#{minorVLAN}-Out"
               puts firstF5Msg    
               f5_command(message, firstF5Msg)
               secondF5Msg = "tmsh delete /net self /#{podName}/SelfIP-LB-#{minorVLAN}"
               puts secondF5Msg    
               f5_command(message, secondF5Msg)   
               thirdF5Msg = "tmsh delete /net self /#{podName}/SelfIP-LB1-#{minorVLAN} "
               puts thirdF5Msg    
               f5_command(message, thirdF5Msg)
               fourthF5Msg = "tmsh delete /net route-domain RD#{minorVLAN}"   
               puts fourthF5Msg        
               f5_command(message, fourthF5Msg)   
               fifthF5Msg = "tmsh delete /net vlan VLAN#{minorVLAN}"               
               puts fifthF5Msg
               f5_command(message, fifthF5Msg) 
 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #remove_container


# Create Service "lcnint"
# sample parameters
#	LBID:		  B
#	PodName:	  pod1.prod
#	ContainerName:	  ACL
#	ServiceName:	  lcnint
#	VIPIP:		  172.24.72.193
#       MajorVLAN:        102
#	ServicePort:	  80
#	ServiceProtocol:  HTTP
#	ClientPort:	  9620
#	ClientProtocol:	  HTTP
#	HealthCheck:	  /lcnint/healthcheck
#	HealthReturn:	  ack
#
# sample commands: 
# create /ltm monitor http /pod1.prod/lcnint-http recv "ack" send "GET /lcnint/healthcheck HTTP/1.0\\r\\n\\r\\n"
# create /ltm pool /pod1.prod/ACL-lcnint-Pool monitor lcnint-http members add { ACL001:9620 ACL002:9620 ACL003:9620 ACL004:9620 ACL005:9620 ACL006:9620 ACL007:9620 ACL008:9620 ACL009:9620 ACL010:9620 ACL011:9620 }
# create /ltm virtual /pod1.prod/ACL-lcnint destination 172.24.72.193%102:80 pool /pod1.prod/ACL-lcnint-Pool profiles add { tcp }

  def create_service(message)
   begin
    parameters = message.parameters
   
    @log.info("LB add_pool command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
 
    podName = parameters.fetch('PodName')
    containerName = parameters.fetch('ContainerName')
    serviceName = parameters.fetch('ServiceName')
    vipIP = parameters.fetch('VIPIP')
    majorVLAN = parameters.fetch('MajorVLAN')
    servicePort = parameters.fetch('ServicePort')
    serviceProtocol = parameters.fetch('ServiceProtocol').downcase
    clientPort = parameters.fetch('ClientPort')
    clientProtocol = parameters.fetch('ClientProtocol').downcase
    healthCheck = parameters.fetch('HealthCheck')
    healthReturn = parameters.fetch('HealthReturn')
    
    @log.info("ContainerName is #{containerName}")
    @log.info("ServiceName is #{serviceName}")
    @log.info("VIP is #{vipIP}") 
    @log.info("MajorVLAN is #{majorVLAN}")
    @log.info("ServicePort is #{servicePort}")
    @log.info("ServiceProtocol is #{serviceProtocol}")
    @log.info("HealthReturn is #{healthReturn}") 
    @log.info("ClientPort is #{clientPort}")
    @log.info("ClientProtocol is #{clientProtocol}")
    @log.info("HealthCheck is #{healthCheck}")
    case parameters.fetch("lb_type")
          when "f5" then 
               firstF5Msg = "tmsh create /ltm monitor #{clientProtocol} /#{podName}/#{serviceName}-#{clientProtocol} recv \"ack\" send \"GET #{healthCheck} HTTP/1.0\\\\r\\\\n\\\\r\\\\n\""
               puts firstF5Msg
               f5_command(message, firstF5Msg) 

               memberString = "";
               for i in 1..11
                 suffix = "%03d" %[i]
                 memberString.concat("#{containerName}#{suffix}:#{clientPort} ")
               end
               secondF5Msg = "tmsh create /ltm pool /#{podName}/#{containerName}-#{serviceName}-Pool monitor #{serviceName}-#{clientProtocol} members add { #{memberString}}" 
               puts secondF5Msg
               f5_command(message, secondF5Msg)  

               thirdF5Msg = "tmsh create /ltm virtual /#{podName}/#{containerName}-#{serviceName} destination #{vipIP}\045#{majorVLAN}:#{servicePort} pool /#{podName}/#{containerName}-#{serviceName}-Pool profiles add { tcp }"
               puts thirdF5Msg
               f5_command(message, thirdF5Msg) 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_service

# to remove a service, issue the 'delete' equivalent of the 'create' commands in 'create_service', but in reverse order
  def remove_service(message)
   begin
    parameters = message.parameters
   
    @log.info("LB add_pool command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
   
    podName = parameters.fetch('PodName')
    containerName = parameters.fetch('ContainerName')
    serviceName = parameters.fetch('ServiceName')    
    clientProtocol = parameters.fetch('ClientProtocol').downcase
   
    @log.info("PodName is #{podName}")
    @log.info("ContainerName is #{containerName}")
    @log.info("ServiceName is #{serviceName}")
    @log.info("ClientProtocol is #{clientProtocol}")
   
    case parameters.fetch("lb_type")
          when "f5" then 
               firstF5Msg = "tmsh delete /ltm virtual /#{podName}/#{containerName}-#{serviceName}"
               puts firstF5Msg
               f5_command(message, firstF5Msg) 
               secondF5Msg = "tmsh delete /ltm pool /#{podName}/#{containerName}-#{serviceName}-Pool" 
               puts secondF5Msg 
               f5_command(message, secondF5Msg) 
               thirdF5Msg = "tmsh delete /ltm monitor #{clientProtocol} /#{podName}/#{serviceName}-#{clientProtocol}"
               puts thirdF5Msg
               f5_command(message, thirdF5Msg)            
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #remove_service

#save_config
 def save_config(message)
   begin
    parameters = message.parameters
    
    @log.info("LB save_config command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh save sys #{parameters.fetch("configtype")}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #save_config

  def add_pool(message)
   begin
    parameters = message.parameters
    
    @log.info("LB add_pool command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm pool #{parameters.fetch("poolname")}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #add_pool

  #add_member
 def add_member(message)
   begin
    parameters = message.parameters
    
    @log.info("LB add_member command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm pool #{parameters.fetch("poolname")} members add {#{parameters.fetch("ip")}:#{parameters.fetch("port")}}")
          # This syntax works in Bash Script { $ip:$port }
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #add_member
  #add_member

def remove_member(message)
   begin
    parameters = message.parameters
    
    @log.info("LB remove_member command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify ltm pool #{parameters.fetch("poolname")} members delete #{parameters.fetch("ip")}:#{parameters.fetch("port")}")
          # This syntax works in Bash Script { $ip:$port }
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #remove_member
  #remove_member

def delete_pool(message)
   begin
    parameters = message.parameters
    
    @log.info("LB delete_pool command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh delete ltm pool #{parameters.fetch("poolname")}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #delete_pool
  #delete_pool
#fixme Need to add Tagging to the interafaces
# def create_vlan(message)
#    begin
#     parameters = message.parameters
    
#     @log.info("LB create_vlan command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
#     #fixme Need to add Tagging to the interafaces    
#     case parameters.fetch("lb_type")
#           when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create net vlan #{parameters.fetch("vlanname")} interfaces add #{parameters.fetch("interfacenumber")}")
#           #This works with Bash { $interfacenumber }
#           when "array" then array_command("...")
#           when "alteon" then alteon_command("Lol, really?")
#           else message.create_fail_msg("Load balancer model unspecified.",9)
#     end
#     return message.create_success_msg("success")
#     rescue F5_command_error
#       return message.create_fail_msg("F5 command failure", 7)
#     end
#   end #create_vlan
#   #create_vlan
# tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")};tmsh create net vlan #{parameters.fetch("vlanname")} tag #{parameters.fetch("vlantagnumber")} interfaces add #{parameters.fetch("interfacenumber")}")


  def create_vlan_addtag_modlacp(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_vlan_addtag command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    #fixme Need to add Tagging to the interafaces    
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create net vlan #{parameters.fetch("vlanname")} tag #{parameters.fetch("vlantagnumber")} interfaces add #{parameters.fetch("interfacenumber")}; tmsh modify net vlan #{parameters.fetch("vlanname")} interfaces modify { all { tagged } #{parameters.fetch("lacpnumber")} }")
          #This works with Bash { $interfacenumber }
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_vlan_addtag
  #create_vlan_addtag

  # def modify_vlan_lacp(message)
  #  begin
  #   parameters = message.parameters
    
  #   @log.info("LB modify_vlan_lacp command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
  #   #fixme Need to add Tagging to the interafaces    
  #   case parameters.fetch("lb_type")
  #         when "f5" then f5_command(message,"tmsh modify net vlan #{parameters.fetch("vlanname")} interfaces modify { all { tagged } #{parameters.fetch("lacpnumber")} }")
  #         #This works with Bash { $interfacenumber }
  #         when "array" then array_command("...")
  #         when "alteon" then alteon_command("Lol, really?")
  #         else message.create_fail_msg("Load balancer model unspecified.",9)
  #   end
  #   return message.create_success_msg("success")
  #   rescue F5_command_error
  #     return message.create_fail_msg("F5 command failure", 7)
  #   end
  # end #modify_vlan_lacp
  # #modify_vlan_lacp

  # def create_netself(message)
  #  begin
  #   parameters = message.parameters
    
  #   @log.info("LB create_netself command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
  #   #fixme need to change ip peramaters to "ip/net"  --> 192.168.1.55/24    
  #   case parameters.fetch("lb_type")
  #         when "f5" then f5_command(message,"tmsh create net self #{parameters.fetch("ip")} vlan #{parameters.fetch("vlanname")}")
  #         when "array" then array_command("...")
  #         when "alteon" then alteon_command("Lol, really?")
  #         else message.create_fail_msg("Load balancer model unspecified.",9)
  #   end
  #   return message.create_success_msg("success")
  #   rescue F5_command_error
  #     return message.create_fail_msg("F5 command failure", 7)
  #   end
  # end #create_netself
  # #create_netself

def create_netself_allowservice(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_netself_allowservice command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
     #fixme the proto:portnumber is not working needs to be like ssh:443   
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create net self #{parameters.fetch("ip")} vlan #{parameters.fetch("vlanname")} allow-service replace-all-with #{parameters.fetch("proto")}:#{parameters.fetch("port")}")
          #This works in Bash { $proto:$port } 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #
  #create_netself_allowservice

def create_netself_in_partition(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_netself_in_partition command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
     #fixme the prot:portnumber isnot working needs to be like ssh:443   
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create net self #{parameters.fetch("ip_mask")} vlan #{parameters.fetch("vlanname")} allow-service all unit 0")
          #This works in Bash { $proto:$port } 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_netself_in_partition

def create_netself_in_partition_floating(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_netself_in_partition_floating command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
     #fixme the prot:portnumber isnot working needs to be like ssh:443   
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create net self #{parameters.fetch("ip_mask")} vlan #{parameters.fetch("vlanname")} allow-service all unit 1 floating enabled")
          #This works in Bash { $proto:$port } 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_netself_in_partition_floating


  #create_netself_allowservice
#create partiotions command needed.
###
## => create a method for crerate partitions 
#
# when "f5" then f5_commands(message,["tmsh create ltm pool #{parameters.fetch("poolname")}","cmd2"])
# root@tw-lb1-a-mgmt(Active)(tmos.auth.partition.pod1.prod)# tmsh modify auth partition pod1.prod create /net self 172.24.64.32/21 Vlan VLAN_101 allow-service all unit 0
#    tmsh modify cli admin-partitions update-partition pod1.pmt; tmsh create net self 172.24.64.111%111/21 Vlan VLAN_111 allow-service all unit 0
#    tmsh modify cli admin-partitions update-partition pod1.pmt; tmsh create net self 172.24.64.111/21 Vlan VLAN_111 allow-service all unit 0

#  in v11 tmsh cd /partitionname ; tmsh create netself 


def create_vs(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_vs command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm virtual #{parameters.fetch("vsname")} destination #{parameters.fetch("ip")}:#{parameters.fetch("port")} pool #{parameters.fetch("poolname")}")
          #This works in Bash { $ip:$port } 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_vs
  #create_vs

 def create_vs_add_vlans_fastl4(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_vs_add_vlans command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm virtual #{parameters.fetch("vsname")} destination #{parameters.fetch("ip")}:#{parameters.fetch("port")} pool #{parameters.fetch("poolname")} vlans add {#{parameters.fetch("vlanname")}} vlans-enabled")
          #This works in Bash { $ip:$port } 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
    return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_vs_add_vlans_fastl4
  #create_vs_add_vlans_fastl4
  
  def create_vs_add_vlans_http(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_vs_add_vlans_http command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm virtual #{parameters.fetch("vsname")} destination #{parameters.fetch("ip")}:#{parameters.fetch("port")} pool #{parameters.fetch("poolname")} vlans add {#{parameters.fetch("vlanname")}} vlans-enabled profiles add { tcp http }")
          #This works in Bash { $ip:$port } 
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
    return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_vs_add_vlans_http
  #create_vs_add_vlans_http

def create_vs_add_vlans_443(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_vs_add_vlans_443 command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm virtual #{parameters.fetch("vsname")} destination #{parameters.fetch("ip")}:#{parameters.fetch("port")} pool #{parameters.fetch("poolname")} vlans add {#{parameters.fetch("vlanname")}} vlans-enabled profiles add { tcp clientssl }")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
    return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_vs_add_vlans_443
  #create_vs_add_vlans_443
####
#  def create_vs_add_vlans(message)
 #  begin
  #  parameters = message.parameters
   # 
   # @log.info("LB create_vs_add_vlans command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
   #     
   # case parameters.fetch("lb_type")
#          when "f5" then f5_command(message,"tmsh create ltm virtual #{parameters.fetch("vsname")} destination #{parameters.fetch("ip")}:#{parameters.fetch("port")} pool #{parameters.fetch("poolname")} vlans add #{parameters.fetch("vlanname")}")
          #This works in Bash { $ip:$port } 
 #         when "array" then array_command("...")
  #        when "alteon" then alteon_command("Lol, really?")
   #       else message.create_fail_msg("Load balancer model unspecified.",9)
  #  end
  #  return message.create_success_msg("success")
  #  rescue F5_command_error
  #    return message.create_fail_msg("F5 command failure", 7)
  #  end
 # end #
  #create_vs_add_vlans

  def create_persistence_rule(message)
   begin
    parameters = message.parameters
    
    @log.info("LB create_persistence_rule command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
        
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm persistence #{parameters.fetch("source_addr")} #{parameters.fetch("pr_srcname")} timeout #{parameters.fetch("timeout")} mask #{parameters.fetch("mask")}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_persistence_rule
  #create_persistence_rule

  def add_persistence_to_vs(message)
   begin
    parameters = message.parameters
    @log.info("LB add_persistence_to_vs command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    #print "Parameters: #{parameters}\n"
    #print "lb_type: #{parameters.fetch("lb_type")}\n"
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm virtual #{parameters.fetch("vsname")} persist replace-all-with {#{parameters.fetch("pr_srcname")}}")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #add_persistence_to_vs
  #add_persistence_to_vs

#fixme  health check url #{parameters.fetch("geturl")} is not being put on  command line as expected have Griffin look at it . 
  def create_hc(message)
   begin
    parameters = message.parameters
    #print 
     @log.info("LB create_hc command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
         # when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm monitor http #{parameters.fetch("monitorname")} send #{parameters.fetch("geturl")} recv #{parameters.fetch("recv")}")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm monitor http #{parameters.fetch("monitorname")} send \"GET #{parameters.fetch("geturl")} HTTP/1.1\\r\\nHost: \\r\\nConnection: Close\\r\\n\\r\\n\" recv \"HTTP/1\.(0|1) (2)\"")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_hc
  #create_hc

 def apply_hc(message)
   begin
    parameters = message.parameters
    @log.info("LB apply_hc command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    #print "Parameters: #{parameters}\n"
    #print "lb_type: #{parameters.fetch("lb_type")}\n"
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm pool #{parameters.fetch("poolname")} monitor #{parameters.fetch("monitorname")}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #apply_hc
  #apply_hc

 def hc_node(message)
   begin
    parameters = message.parameters
    #print "\n\n\n\n******************WTF******************\n\n\n\n"
    print ("#{message}")
    @log.info("LB hc_node command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    #print "Parameters: #{parameters}\n"
    #print "lb_type: #{parameters.fetch("lb_type")}\n"
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm node #{parameters.fetch("node")} monitor #{parameters.fetch("monitorname")}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #hc_node
  #hc_node
 def create_cookie(message)
   begin
    parameters = message.parameters
    @log.info("LB create_cookie command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm persistence cookie #{parameters.fetch("pr_cookie")} expiration {#{parameters.fetch("expiration")}}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_cookie
  #create_cookie

  def apply_cookie_to_vs(message)
   begin
    parameters = message.parameters
    @log.info("LB apply_cookie command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm virtual #{parameters.fetch("vsname")} profiles replace-all-with { http } persist replace-all-with {#{parameters.fetch("pr_cookie")}}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #apply_cookie
  #apply_cookiea 

  def add_snat_automap(message)
   begin
    parameters = message.parameters
    @log.info("LB add_snat_automap command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm virtual #{parameters.fetch("vsname")} snat automap")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #add_snat_automap
  #add_snat_automap

 def add_snat(message)
   begin
    parameters = message.parameters

    @log.info("LB add_snat command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh create ltm snat #{parameters.fetch("snatname")} translation #{parameters.fetch("translation-ip")} origins add {#{parameters.fetch("origin")}} vlans-enabled vlans add {#{parameters.fetch("vlanname")}}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #add_snat
  #add_snat modify ltm snat VLAN101-SNAT1-64.7 vlans-enabled  vlans add { VLAN_2003 }

def modify_snat_add_vlans(message)
   begin
    parameters = message.parameters

    @log.info("LB modify_snat_add_vlans command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm snat #{parameters.fetch("snatname")} vlans-enabled vlans add {#{parameters.fetch("vlanname")}}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #modify_snat_add_vlans
  #modify_snat_add_vlans 
   
def modify_snat_remove_vlans(message)
   begin
    parameters = message.parameters

    @log.info("LB modify_snat_remove_vlans command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify cli admin-partitions update-partition #{parameters.fetch("partitionname")}; tmsh modify ltm snat #{parameters.fetch("snatname")} vlans delete {#{parameters.fetch("vlanname")}}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #modify_snat_remove_vlans
  #modify_snat_remove_vlans 

   #create auth partition pod3.prod description pod3 default-route-domain 101
 def create_partition_add_route_domain(message)
   begin
    parameters = message.parameters
    @log.info("LB create_partition_add_route_domain command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh create auth partition #{parameters.fetch("podname")} description #{parameters.fetch("description")} default-route-domain #{parameters.fetch("domain_id")} strict enabled")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #create_partition_add_route_domain
  #create_partition_add_route_domain
  
def add_route_domain(message)
   begin
    parameters = message.parameters
    @log.info("LB create_partition_add_route_domain command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh create net route-domain #{parameters.fetch("domain_id")} vlans add #{parameters.fetch("{ vlanname }")} description #{parameters.fetch("description")} strict enabled")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #add_route_domain
  #add_route_domain
def modify_route_domain(message)
   begin
    parameters = message.parameters
    @log.info("LB modify_route_domain command received from #{message.from}: #{message.command} #{message.parameters.to_s}")
    case parameters.fetch("lb_type")
          when "f5" then f5_command(message,"tmsh modify net route-domain #{parameters.fetch("domain_id")} vlans #{parameters.fetch("option")} {#{parameters.fetch("vlanname")}}")
          when "array" then array_command("...")
          when "alteon" then alteon_command("Lol, really?")
          else message.create_fail_msg("Load balancer model unspecified.",9)
    end
    return message.create_success_msg("success")
    rescue F5_command_error
      return message.create_fail_msg("F5 command failure", 7)
    end
  end #modify_route_domain
  #modify_route_domain
end
