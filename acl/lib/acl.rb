# ACL
module ACL
  
  def self.current_user=(user)
    @@current_user = user
  end
  
  def self.current_user
    @@current_user
  end
  
  def self.clear_cache
    @cache = {}
  end
  
  def self.has_access?(user, url_options = {})
    if user == :false
      return true
    end
    
    puts url_options.inspect
    @cache ||= {}
    if !@cache[url_options].nil?
      return @cache[url_options]
    end
    
    if url_options.is_a? Hash
      controller = url_options[:controller]
      action = url_options[:action]
      if !(ret = @cache["#{controller}:#{action}"] = Rails.cache.read("ACL:Access:#{user.id}:#{controller}:#{action}")).nil?
        puts "Cached 1"
        return ret
      end
    else
      r = nil
      url_options = "/#{url_options}" if url_options.first != '/'
      url_options.gsub!(/\?.*/, "")
      if !(ret = @cache[url_options] = Rails.cache.read("ACL:Access:#{user.id}:#{url_options}")).nil?
        puts "Cached 3"
        return ret
      end
      ActionController::Routing::Routes.routes.each do |route|
        r = route.recognize(url_options, {:method => :get}) and break
      end
      if r.nil?
        puts "UNMATCHED: #{url_options}"
        return @cache[url_options] = false
      end
      controller = r[:controller]
      action = r[:action]
    end
    if !(ret = @cache["#{controller}:#{action}"] = Rails.cache.read("ACL:Access:#{user.id}:#{controller}:#{action}")).nil?
      puts "Cached 2"
      return ret
    end
    
    if controller.blank? or action.blank?
      throw "hurr"
    end
    user_id = user.id
    if !(default_role_id = Rails.cache.read("ACL:Default_Role_ID:E#{user.entity.id}"))
      Rails.cache.write("ACL:Default_Role_ID:E#{user.entity.id}", default_role_id = user.entity.default_role_id)
    end
    puts("Access check: Controller: #{controller}, Action: #{action}, User: #{user.to_s} (#{user_id}), Entity: #{user.entity} (#{user.entity.id})")
    if ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM user_roles ur RIGHT JOIN role_permissions rp ON rp.role_id = ur.role_id INNER JOIN permissions p ON rp.permission_id = p.id WHERE (ur.user_id = #{user_id} OR rp.role_id = #{default_role_id}) AND ((p.controller = '#{controller}' AND FIND_IN_SET('#{action}', p.action) IS NOT NULL) OR (p.controller = '#{controller}' AND p.action IS NULL) OR (p.controller IS NULL AND FIND_IN_SET('#{action}', p.action) IS NOT NULL) OR (p.controller IS NULL AND p.action IS NULL));").to_i > 0
      puts("Access granted")
      Rails.cache.write("ACL:Access:#{user.id}:#{controller}:#{action}", true)
      Rails.cache.write("ACL:Access:#{user.id}:#{url_options}", true)
      return @cache[url_options] = @cache["#{controller}:#{action}"] = true
    else
      puts("Access denied")
      Rails.cache.write("ACL:Access:#{user.id}:#{controller}:#{action}", false)
      Rails.cache.write("ACL:Access:#{user.id}:#{url_options}", false)
      return @cache[url_options] = @cache["#{controller}:#{action}"] = false
    end
  end


  
  module Base
    def self.included(klass)
      klass.send(:extend, ACL::Base::ControllerClassMethods)
      klass.send(:include, ACL::Base::ControllerInstanceMethods)
    
      
      WillPaginate::Finder::ClassMethods.class_eval do
        alias_method :wp_count_original, :wp_count
        def wp_count(options, args, finder)
          wp_count_original ((args.length >= 2 and args[1][:conditions]) ? (options.merge(:conditions => args[1][:conditions])) : options), args, finder
        end
      end if defined? WillPaginate
    end
    
    

    
    module ControllerClassMethods
      
      def enable_acl(*args)
        prepend_before_filter :set_acl_current_user
        prepend_before_filter do |c|
          acl_options = args.extract_options!
          acl_options[:redirect_url] ||= "/"
          acl_options[:error_message] ||= "Access denied."
          acl_options[:models] ||= []
          c.send(:set_acl_options, acl_options)
        end

        before_filter :check_access
      end
    end
    

    module ControllerInstanceMethods
      
      def set_acl_options(options)
        @acl_options = options
      end
      
      def set_acl_current_user
        current_user != :false and ACL.current_user = current_user
      end
      
      def check_access
        
        ACL.clear_cache
        if !has_access?
          flash[:error] = @acl_options[:error_message]
          LogEvent.log("ACL", "Access denied to #{request.request_uri} for #{current_user}", "Referred from #{request.referer}", current_user, request.remote_ip)
          redirect_to @acl_options[:redirect_url]
          return
        end
        
        model = nil
        
        self.class.before_filters.each do |f|
          if f.to_s =~ /^get_([a-z]+)/ and self.instance_variable_names.include?("@#{$1}") and self.class.filter_chain.select { |filter| filter.method == f }.first.send(:should_run_callback?, self)
            self.send(f)
            model = self.instance_variable_get("@#{$1}")
            break
          end
        end
        
        return if model.nil?
        
        if model.respond_to? :accessable_by? and !model.accessable_by? current_user
          flash[:error] = @acl_options[:error_message]
          LogEvent.log("ACL", "Access denied to #{model.class.to_s} ID: #{model.id} - #{model.to_s}", "Referred from #{request.referer}", current_user, request.remote_ip)
          redirect_to @acl_options[:redirect_url]
          return
        end
        
      end
      
      def has_access?
        controller = params[:controller]
        action = action_name
        
        ACL.has_access?(current_user, {:controller => controller, :action => action})
      end
    end
    
  end
  
end