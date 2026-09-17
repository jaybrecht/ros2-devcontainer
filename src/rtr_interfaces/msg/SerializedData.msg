int8 INDETERMINATE=0
int8 JSON=1
int8 PROTOBUF=2
int8 YAML=3

# Type of the serialization encoding to use
int8 encoding

# The data type that this SerializedData represents.
# If you are using JSON, XML, etc. then this would hold the schema string.
string data_type

# The serialized data payload
string data
