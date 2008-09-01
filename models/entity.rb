class Entity < ActiveRecord::Base
  acts_as_nested_set


  class << self
    def top_level
      self.find_all_by_parent_id(nil, :order => 'name')
    end
    
    alias_method :find_every_original, :find_every
    def find_every(*args)
      options = args.extract_options!
      if options.key? :select and options.key? :readonly and options.key? :include
        return find_every_original(options)
      end
      
      if (ACL.current_user.roles.map(&:name) & %w(staff superadmin)).length > 0
        return find_every_original(options)
      end
      @@fetched_ids ||= ACL.current_user.entity_ids
      if options[:conditions].nil?
        options[:conditions]= ['id IN (?)', @@fetched_ids]
      elsif options[:conditions].is_a? Hash
        if !options[:conditions][:id]
          options[:conditions][:id] = @@fetched_ids
        end
      elsif options[:conditions].is_a? String
        options[:conditions] += " AND id IN (#{@@fetched_ids.join(", ")})"
      elsif options[:conditions].is_a? Array
        options[:conditions][0] += " AND id IN (?)"
        options[:conditions] << @@fetched_ids
      else
        
      end
      find_every_original(options)
    end
    
    
  end

  def subentity_ids
    ActiveRecord::Base.connection.select_all("SELECT id FROM entities WHERE id != #{id} AND lft >= #{lft} AND rgt <= #{rgt};").map { |e| e['id'].to_i } # <snip> end
  end
  
  def entity_ids
    ([self.id] + subentity_ids)
  end

  # <snip>

end
