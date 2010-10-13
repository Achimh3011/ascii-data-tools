require 'set'
require 'forwardable'
require 'ascii-data-tools/record_type/field'
require 'ascii-data-tools/record_type/builder'
require 'ascii-data-tools/record_type/normaliser'
require 'ascii-data-tools/record_type/decoder'
require 'ascii-data-tools/record_type/encoder'

module AsciiDataTools
  module RecordType
    module FixedLengthType
      include Decoder::RecordDecoder
      include Encoder::RecordEncoder
      include Normaliser::Normaliser
      
      def total_length_of_fields
        @total_length ||= fields.inject(0) {|sum, field| sum + field.length}
      end
    end
    
    class Type
      include FixedLengthType
      extend Forwardable
      attr_reader :name
      
      def_delegator  :fields, :names, :field_names
      def_delegator  :fields, :with_name, :field_with_name
      def_delegator  :fields, :with_index, :field_with_index
      def_delegators :fields, :number_of_content_fields, :length_of_longest_field_name, :constraints_description, :fields_with, :names_of_normalised_fields
      
      def initialize(name, content_fields = Field::Fields.new)
        @name = name
        @fields_by_type = {:content => content_fields}
      end
      
      protected
      def fields
        @fields_by_type[:content]
      end
    end
    
    class UnknownType < Type
      include Decoder::UnknownRecordDecoder
      UNKNOWN_RECORD_TYPE_NAME = "unknown"
      
      def initialize
        super(UNKNOWN_RECORD_TYPE_NAME, Field::Fields.new([Field::Field.new("UNKNOWN")]))
      end      
    end
    
    class TypeWithFilenameRestrictions < Type
      def initialize(type_name, fields = Field::Fields.new, filename_constraint = Field::FilenameConstraint.new)
        super(type_name, fields)
        @filename_constraint = filename_constraint
      end
      
      def matching?(ascii_string, context_filename = nil)
        @filename_constraint.satisfied_by?(context_filename) and super(ascii_string)
      end
      
      def filename_should_match(regexp)
        @filename_constraint = Field::FilenameConstraint.satisfied_by_filenames_matching(regexp)
        self
      end
      
      def constraints_description
        descriptions = [@filename_constraint.to_s, super].reject {|desc| desc.empty?}
        descriptions.join(", ")
      end
    end

    class TypeDeterminer
      def initialize(type_repo = RecordTypeRepository.new)
        @all_types = type_repo
        @previously_matched_types = RecordTypeRepository.new
      end

      def determine_type_for(encoded_record_string, context_filename = nil)
        matching_type = 
          @previously_matched_types.find_for_record(encoded_record_string, context_filename) || 
          @all_types.find_for_record(encoded_record_string, context_filename)
        if matching_type.nil?
          return UnknownType.new
        else
          @previously_matched_types << matching_type
          return matching_type
        end
      end
    end
    
    class RecordTypeRepository
      include Enumerable
      include Builder::TypeBuilder
      
      def initialize(types = [])
        @types = Set.new(types)
      end

      def <<(type)
        @types << type
      end

      def clear
        @types.clear
      end

      def find_by_name(name)
        detect {|type| type.name == name}
      end

      alias :type :find_by_name

      def each(&block)
        @types.each(&block)
      end

      def find_for_record(encoded_record_string, context_filename)
        @types.detect {|type| type.matching?(encoded_record_string, context_filename) }
      end
      
      def for_names_matching(matcher, &block)
        if matcher.is_a?(Regexp)
          select {|type| type.name =~ matcher}.each {|found_type| block[found_type]}
        elsif matcher.is_a?(Proc)
          select {|type| matcher[type.name]}.each {|found_type| block[found_type]}
        end
      end
      
      def record_type(name, props = {}, &definition)
        self << build_type(name, props, &definition)
      end
    end
  end
end