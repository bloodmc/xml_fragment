require "nokogiri"

module Puppet
module Util
	class XmlFile		
		def initialize(path)
			@does_exist = false
			@path = path

			if File.file?(@path)
				@does_exist = true
				xml_file = File.open(@path, 'r')
				# We remove namespaces to avoid xpath requiring them during searches
				@document =  Nokogiri::XML(xml_file,&:noblanks).remove_namespaces!
			end		
		end

		def file_exists
			@does_exist
		end

		# Find all nodes for a give URI
		def find(xpath)
			@document.xpath(xpath)
		end

		def matches(xpath, value)
			does_match = true			

			candidates = find(xpath)

			if !candidates.empty?
				candidates.each do |node|
					if !node_matches(node, value)
						does_match = false
						break
					end
				end
			else
				does_match = false
			end
			
			does_match
		end

		def node_matches(node, value)
			if !node || node.empty?
				return false
			end
			# Is this a text only node?
			if node.type == 3
				if value && value.has_key?("value") && value["value"] != "" && node.text != value["value"]
					return false
				end
			end

			if value.has_key?("attributes") && node.has_attribute?
				value["attributes"].each do |key, value|
					test_attribute = node.attribute(key)

					if !test_attribute || test_attribute.value != value
						return false											
					end
				end							
			elsif value.has_key?("attributes") != node.has_attribute?
				return false
			end

			return true
		end

		def remove_elements(xpath)
			nodes = @document.xpath(xpath)
			nodes.each do |node|
				node.children.each do |child|
					if !child.attribute("Puppet::Util::XmlFile.Managed")
						Puppet.debug "Removing unmanaged node #{child}"
						child.remove
					end
				end
			end
			nodes
		end

		def exists(xpath)
			!@document.xpath(xpath).empty?
		end

		def create_xml(xpath, tag, content)
			nodes = xpath.split("/")
			if nodes[0] == ""
				nodes = nodes.drop(1)
			end

			nodes.push(tag)
			builder = Nokogiri::XML::Builder.new do |xml|
				recursor = ->(*) do
					if nodes.size > 1
						xml.send(nodes.shift, &recursor)
					else
						# send tag with content
						xml.send(nodes.shift, content)
					end
				end
				recursor.call
			end
			xml_file = File.new(@path, "w")
			xml_file.write(builder.to_xml)
			xml_file.close
			xml_file = File.open(@path, 'r')
			@document =  Nokogiri::XML(xml_file,&:noblanks).remove_namespaces!
		end

		def set_tag(parent_xpath, tag, tag_xpath, value)
			if !@document
				return create_xml(parent_xpath, tag, value)
			end
			matches = nil
			parent_found = false
			
			Puppet.notice("Xpath: #{parent_xpath}")

			@document.xpath(parent_xpath).each do |node|
				if node.element?
					was_found = false
					parent_found = true
					
					node.xpath("./#{tag}#{tag_xpath}").each do |child|
						was_found = true

						if value && value.has_key?("value")
							child.content = value["value"]
						end
						
						if value && value.has_key?("attributes")
							value["attributes"].each do |key, value|
								child.set_attribute(key, value)
							end
						end					
					end			

					if !was_found												
						new_element = Nokogiri::XML::Node.new(tag, @document)
						
						if value.has_key?("value")
							new_element.content = value["value"]
						end
						
						if value.has_key?("attributes")
							new_element.add_attributes(value["attributes"])
						end						

						node.add_child(new_element)
					end
				end
			end

			raise ArgumentError, "Unable to set <#{tag}>. No parents found for the xpath #{parent_xpath}" if !parent_found
		end

		def remove_tag(xpath)			
			@document.xpath(xpath).each do |node|
				node.remove
			end				
		end

		def save
			File.write(@path, @document.to_xml)
		end

		# Static helper methods
		def self.node_to_hash(node)
			new_hash = Hash.new

			if node.element_children.empty? && node.text && node.text != ""
				new_hash["value"] = node.text
			end

			if !node.attributes.empty?
				new_hash["attributes"] = Hash.new
				
				node.attributes.each do |a|
					new_hash["attributes"][a[0]] = a[1]
				end
			end	

			Puppet.debug "Converted hash: #{new_hash}"			

			new_hash
		end

		private
		def build_xpath(xpath, tag, uri)
			xpath + (xpath.end_with?("/") ? "" : "/") + build_tag_uri(tag, uri)
		end

		def build_tag_uri(tag, uri)
			(tag ? tag : "*") + (uri ? ("[@uri=\"" + uri + "\"]") : "")
		end
	end
end
end