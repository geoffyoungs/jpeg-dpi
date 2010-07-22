#!/usr/bin/ruby

require 'optparse'

begin
	require 'mmap'
	require 'fileutils'
	$mmap = true
rescue LoadError
	$mmap = false
end

class DeRePacker
	class << self
	def field(template, len, id, valid = nil)
		@fields ||= []
		@fields << { :template => template, :len => len, :id => id, :valid => valid }
		module_eval { attr_accessor(id) }
	end
	attr_accessor :fields
	end
	def initialize(str)
		offset = 0
		self.class.fields.each do |field|
			val = str[offset..(offset+field[:len])].unpack(field[:template])
			val = val.size == 1 ? val[0] : val
			unless field[:valid].nil? or field[:valid] === val
				raise ScanError, "#{val.inspect} !== #{field[:valid]} at offset #{offset}-#{offset+field[:len]}"	
			end
			instance_variable_set("@#{field[:id]}", val)
			offset += field[:len]
		end
	end
	def to_s
		str = ''
		self.class.fields.each do |field|
			val = instance_variable_get("@#{field[:id]}")
			val = [val] unless val.is_a?(Array)
			str += val.pack(field[:template])
		end
		str
	end
end

class JFIF < DeRePacker
	APP0 = "\xff\xd8\xff\xe0"
	ID = "JFIF\0"
	field 'a4', 4, :magic, APP0
	field 'n',  2, :len
	field 'a5', 5, :identifier, ID
	field 'CC', 2, :version
	field 'C',  1, :units
	field 'n',  2, :xdensity
	field 'n',  2, :ydensity
	field 'C',  1, :thumbnail_width
	field 'C',  1, :thumbnail_height
end



if __FILE__ == $0

source    = nil
target    = nil
write_dpi = false
modify    = false
dpi       = 300

OptionParser.new do |opts|
	opts.banner = "Usage: jpeg-dpi.rb [options] <source-jpeg> [<target-jpeg>]"

	opts.on('-d N', '--dpi N', Integer, 'Set DPI') do |val|
		dpi = val
	end
	opts.on('-w', '--write', 'Write DPI') do
		write_dpi = true
	end
	opts.on('-r', '--read', 'Read DPI') do
		write_dpi = false
	end
	opts.on('-m', '--modify') do
		write_dpi = true
		modify = true
	end
end.parse!

source ||= ARGV[0]

if modify
	target = source
else
	target ||= ARGV[1] || source.sub(/[.]jpe?g$/i,'')+'.dpi_'+dpi.to_s+'.jpg'
end

if $mmap
	len = [File.size(source),256].min
	if write_dpi
		FileUtils.cp(source, target) unless target == source
		mmap = Mmap.new(target, "a", "offset" => 0, 'length' => len)
	else
		mmap = Mmap.new(source, 'r', 'offset' => 0, 'length' => len)
	end
	data = mmap[0...len]
	puts "Modify in-place" if $DEBUG
else
	data = File.open(source) { |fp| 
		if write_dpi
			fp.read
		else
			fp.read(256)
		end
	}
	puts "Re-write whole file" if $DEBUG
end

begin
	jfif = JFIF.new(data)
rescue ScanError => e
	mmap.unmap if $mmap
	STDERR.puts "Not a recognised JFIF JPEG"
	exit 1
end

if write_dpi
	jfif.units = 1
	jfif.xdensity = dpi
	jfif.ydensity = dpi

	str = jfif.to_s

	if $mmap
		mmap[0,str.size] = str
		mmap.unmap
	else
		File.open(target, "wb") {|fp|
			fp.write(str)
			fp.write(data[str.size..-1])
		}
	end
else
	mmap.unmap if $mmap
	STDOUT.write("Units: ")
	case jfif.units
	when 0
		puts "unspecified"
	when 1
		puts "dots per inch"
	when 2
		puts "dots per cm"
	else
		puts "invalid"
	end
	puts "Resolution: #{jfif.xdensity}x#{jfif.ydensity}"
end

end
