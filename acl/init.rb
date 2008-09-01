# Include hook code here
require 'acl'

ActionController::Base.send( :include, ACL::Base )