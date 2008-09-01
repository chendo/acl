class Post < ActiveRecord::Base

  class << self
    alias_method :find_every_original, :find_every
    def find_every(*args)
      options = args.extract_options!
      if (ACL.current_user.roles.map(&:name) & %w(staff superadmin)).length > 0
        return find_every_original(options)
      end
      @@fetched_ids ||= ACL.current_user.entity_ids
      if options[:conditions].nil?
        options[:conditions]= ['entity_id IN (?)', @@fetched_ids]
      elsif options[:conditions].is_a? Hash
        if options[:conditions][:id]
          debugger
        else
          options[:conditions][:id] = @@fetched_ids
        end
      elsif options[:conditions].is_a? String
        options[:conditions] += " AND entity_id IN (#{@@fetched_ids.join(", ")})"
      elsif options[:conditions].is_a? Array
        options[:conditions][0] += " AND entity_id IN (?)"
        options[:conditions] << @@fetched_ids
      else
        debugger
      end
      find_every_original(options)
    end
  end
  # <snip>
end
