# Dumps Backpack access notes into KeePassX XML

require 'rubygems'
require 'xmlsimple'
require 'yaml'
require 'backpack'

class Backpack
  # Find backpack page matching regexp, or return nil if none is found
  # N.B. Will only find first matching page
  def find_page(title, regexp_options = Regexp::IGNORECASE)
    pages = self.list_pages['pages'][0]['page']
    search_regexp = Regexp.new(title, regexp_options)
    page = pages.detect{|p| p['title'] =~ search_regexp}
    if page
      page_id = page['id']
      self.show_page(page_id)['page'][0]
    end
  end

  # Find backpack note matchig regexp, or return nil if none is found
  # Requires the page to be an XmlSimple-generated hash, as returned by
  # show_page etc. N.B. Will only find first matching note
  def find_note(page, title, regexp_options = Regexp::IGNORECASE)
    search_regexp = Regexp.new(title, regexp_options)
    note = page['notes'].detect{|n| n['note'][0]['title'] =~ search_regexp}
    if note
      note['note'][0]
    end
  end

  module Keepassx
    require 'fastercsv'
    require 'builder'
    
    # Expects a hash of page title regexp strings and icon numbers
    def to_keepassx_xml(pages, indent = 0)
      xml = Builder::XmlMarkup.new(:indent => indent)
      xml.declare! :DOCTYPE, :KEEPASSX_DATABASE
      xml.database do |xml|
        pages.each_pair do |page, icon|
          note = Backpack::Keepassx::AccessNote.new(self, page, icon)
          note.to_xml(xml)
        end
      end
    end
        
    class AccessNote
      attr_accessor :title, :content, :created_at, :icon
  
      # Needs reference to Backpack object and a string regexp for page title
      def initialize(backpack, page_title, icon)
        page = backpack.find_page(page_title)
        note = backpack.find_note(page, 'access')
        
        @title      = page_title
        @icon       = icon.is_a?(Fixnum) ? icon : 48
        @content    = note['content']
        @created_at = note['created_at']
      end

      # Needs Builder::XmlMarkup object passed in
      def to_xml(xml)
        table = self.to_csv_table
        created_at = @created_at.gsub(/\s/,"T") # Funny KeePassX XML datetime

        # Headers that are not used explicitly will be turned into the comment
        headers = table.headers - %w{Name Username Password URL} - [nil]

        xml.group do |xml|
          xml.title(@title)
          xml.icon(@icon)

          table.each do |row|
            unless row.header_row?
              xml.entry do |xml|
                xml.title(row['Name'])
                xml.username(row['Username'])
                xml.password(row['Password'])
                xml.url(row['URL'])
                xml.comment do |xml|
                  headers.each do |header|
                    xml << "#{header}: #{row[header]}<br/>"
                  end
                end
                xml.icon(0)
                xml.creation(created_at)
                xml.lastaccess(created_at)
                xml.lastmod(created_at)
                xml.expire("Never")
              end
            end
          end
        end
      end
      
      # Returns FasterCSV::Table with headers
      def to_csv_table
        # Get only the lines starting and ending with '|' and ignore leading
        # and trailing whitespace
        textile_table = @content.scan(/^\s*(\|.*\|)\s*$/).join("\n")
        
        # Header converter to remove '_.' Textile table header syntax
        cleanup_header = lambda {|h| h.nil? ? nil : h.gsub(/_\./,'') }

        FasterCSV.parse(textile_table, :col_sep => '|',
                                       :headers => :first_row,
                                       :return_headers => true,
                                       :write_headers => true,
                                       :header_converters => cleanup_header)
      end                                                
    end
  end
  
  include Keepassx
end

if __FILE__ == $0
  begin
    backpack = YAML::load(IO.read('backpack.yml'))
  rescue
    fail "Could not load configuration file backpack.yml"
  end

  begin
    pages = YAML::load(IO.read('keepassx.yml'))
  rescue
    fail "Could not load configuration file keepassx.yml"
  end

  bp = Backpack.new(backpack['username'], backpack['token'])
  puts bp.to_keepassx_xml(pages, 0)
end

# To output CSV back.
# TODO Convert headers back to Textile TH syntax
#table.to_csv(:col_sep => '|',
#             :header_converters => lambda {|h| h.nil? ? nil : "_.#{h}"}) # Doesn't do anything