import json
import io

# kind: module, typename, union, struct, array, f32, i32, u32, bool, void, char, variadic-param, pointer, namedType
# kind: enum-constant, macro

# TODO
# type aliases see utf32

# exclude oc_* from any string
def prefix_trim_oc(name):
    if name.startswith("oc_"):
        return name[3:]

    return name

def get_type_name_or_kind(obj):
    result = obj["kind"] # basic identifiers like f32, int, etc land here
    
    # if it contains an orca name, use that one instead
    if "name" in obj:
        result = prefix_trim_oc(obj["name"]) # names need to be trimmed

    return result

# try using the object kind
# if kind is namedType -> get the namedType name
# if its a pointer do a pointer type or rawptr
def get_inner_kind(obj):
    result = get_type_name_or_kind(obj)
    output = result

    if result == "pointer":
        inner_type = obj["type"]
        result = get_type_name_or_kind(inner_type)

        # convert void to odins rawptr
        if result == "void":
            output = "rawptr"
        else:
            output = "^" + result
    elif result == "namedType":
        inner_type = obj["type"]
        result = get_type_name_or_kind(inner_type)
        output = result

    return output

# generate a single field key & value pair
def gen_param(obj, file):
    name = check_field_name(obj["name"]) # can be ... !
    
    # convert variadic-param to odin #c_vararg args: ..any
    if name == "...":
        file.write("#c_vararg args: ..any")
        return

    if name == "context": # context is a keyword in odin
        name = "_context" 

    variable_output = get_inner_kind(obj["type"])
    file.write(f"{name}: {variable_output}")

# generate a multi or single line doc dependant on whats provided
def gen_doc(obj, file, indent):
    indent_str = indent_string(indent)
    if isinstance(obj, list):
        file.write(f"{indent_str}/*\n")
        for line in obj:
            file.write(f"{indent_str}{line}\n")
        file.write(f"{indent_str}*/\n")
    else:
        file.write(f"{indent_str}// {obj}\n")

# if the doc exists write it
def try_gen_doc(obj, file, indent):
    if "doc" in obj:
        gen_doc(obj["doc"], file, indent)

# generate a procedure declation with the parameters and its return type
def gen_proc(obj, file, indent):
    kind = obj["kind"]
    name = prefix_trim_oc(obj["name"])
    brief = obj["brief"] if "brief" in obj else "" 

    try_gen_doc(obj, file, indent)
    indent_str = indent_string(indent)
    file.write(f"{indent_str}{name} :: proc(")

    # write params
    param_count = 0
    for param in obj["params"]:
        if param_count > 0:
            file.write(", ")

        gen_param(param, file)
        param_count += 1

    file.write(")")

    # write return type when not void
    ret = obj["return"]
    if ret["kind"] != "void":
        ret_kind = get_inner_kind(ret)
        file.write(f" -> {ret_kind}")

    # finish
    file.write(" ---\n")

# add indentation 
def indent_string(indent):
    return "  " * indent

# write spacers and actual module docs
def gen_module_doc(obj, file):
    brief = obj["brief"]
    spacer = "//" * 40
    file.write(spacer + "\n")
    file.write(f"// {brief}\n")
    file.write(spacer + "\n" * 2)

# easier builtins instead of struct+unions
type_builtins = {
    "vec2": "[2]f32",
    "vec3": "[3]f32",
    "vec2i": "[2]i32",
    "vec4": "[4]f32",
    "mat2x3": "[2][3]f32", # TODO
    "rect": "[4]f32",
    "color": "[4]f32",
    "str8": "string",

    "ui_layout_align": "[2]ui_align",
    "ui_box_size": "[2]ui_size",
    "ui_box_floating": "[2]bool",
    "utf32": "rune",
}

# generate a default builtin instead of complex xy or xywh C struct+union pairs
def gen_type_builtins(name, file, indent):
    if name in type_builtins:
        indent_str = indent_string(indent)
        output = type_builtins[name]
        file.write(f"{indent_str}{name} :: {output}\n\n")
        return True

    return False

# get the enum size (u64, i32, etc)
def get_enum_sizing(obj):
    return obj["type"]["kind"]

# since prefixes dont always match the enum name, the table is easier
enum_prefixes_specific = {
    "OC_LOG_LEVEL_",
    "OC_EVENT_",
    "OC_KEY_",
    "OC_SCANCODE_",
    "OC_KEYMOD_",
    "OC_MOUSE_",
    "OC_FILE_DIALOG_",
    "OC_FILE_OPEN_",
    "OC_FILE_ACCESS_",
    "OC_FILE_SEEK_",
    "OC_IO_ERR_",
    "OC_GRADIENT_BLEND_",
    "OC_COLOR_SPACE_",
    "OC_JOINT_",
    "OC_CAP_",
    "OC_INPUT_TEXT_",
    "OC_UI_AXIS_",
    "OC_UI_ALIGN_",
    "OC_UI_SIZE_",
    "OC_UI_STYLE_",
    "OC_UI_SEL_",
    "OC_UI_FLAG_",
    "OC_UI_FLAG_",
    "OC_UI_EDIT_MOVE_",
}

# since the hashset above is unsorted these should be checked last
enum_prefixes_broad = {
    "OC_FILE_",
    "OC_UI_",
    "OC_IO_",
}

# fixup enum names based on prefixes
def simplify_enum_name(name):
    for prefix in enum_prefixes_specific:
        if name.startswith(prefix):
            return name[len(prefix):]

    # check last
    for prefix in enum_prefixes_broad:
        if name.startswith(prefix):
            return name[len(prefix):]

    return name

# safety check since enum field names cant be only numbers
# 0 would be turned to _0
def check_enum_name_decimal(name):
    if name.isdecimal():
        return "_" + name

    return name

# generates an odin enum e.g. log_level :: enum { ... }
def gen_enum(obj, file, name, indent):
    indent_str = indent_string(indent)
    singleton = len(obj["constants"]) <= 1

    # write enum description when not a singleton
    if not singleton:
        enum_sizing = get_enum_sizing(obj)
        file.write(f"{indent_str}{name} :: enum {enum_sizing} {{\n")
        fields_indent_str = indent_string(indent + 1)
    else:
        fields_indent_str = indent_str

    # write enum content from objects
    for const in obj["constants"]:
        const_name = simplify_enum_name(const["name"])
        const_name = check_enum_name_decimal(const_name)
        const_value = const["value"]

        # write docs if they exist
        if "doc" in const:
            const_docs = const["doc"]
            file.write(f"{fields_indent_str}// {const_docs}\n")

        # make it a constant instead of an enum asignment
        assignment = "::" if singleton else "="

        file.write(f"{fields_indent_str}{const_name} {assignment} {const_value}")
        file.write("\n" if singleton else ",\n")

    if singleton:
        file.write("\n")
    else:
        file.write(f"{indent_str}}}\n\n")


# any oddities that need to be checked for field
reserved_field_names = {
    "string", # think this is still allowed but eh
}

# insert a _ before an identifier that may be invalid
def check_field_name(name):
    for reserved in reserved_field_names:
        if reserved == name:
            return "_" + name

    return name

# generate raw unions fields
def gen_union_fields(obj, file, indent):
    if "fields" not in obj:
        print(f"FIELDS MISSED in union")
        return

    indent_str = indent_string(indent)
    for field in obj["fields"]:
        field_name = check_field_name(field["name"])
        field_kind = get_inner_kind(field["type"])

        # name can be empty
        if field_name == "":
            field_name = "_"

        # generate inner structs within a union
        if field_kind == "struct":
            gen_struct(field["type"], file, field_name, indent)

            # always comma separate
            file.write(",\n")
        else:
            file.write(f"{indent_str}{field_name}: {field_kind},\n")

# write struct fields from objects
def gen_struct_fields(obj, file, indent):
    indent_str = indent_string(indent)
    for field in obj["fields"]:
        field_name = check_field_name(field["name"])
        variable_output = get_inner_kind(field["type"])

        # write docs if they exist
        if "doc" in field:
            field_docs = field["doc"]
            file.write(f"{indent_str}// {field_docs}\n")

        # convert inner unions to raw_unions structs
        if variable_output == "union":
            if field_name == "":
                field_name = "_"

            file.write(f"{indent_str}{field_name}: struct #raw_union {{\n")
            variable_type = field["type"]
            gen_union_fields(variable_type, file, indent + 1)
            file.write(f"{indent_str}}},\n")
        else:
            file.write(f"{indent_str}{field_name}: {variable_output},\n")

# generate an odin struct with its fields
def gen_struct(obj, file, name, indent):
    # if a struct doesnt have fields, skip it
    if "fields" not in obj:
        return

    indent_str = indent_string(indent)

    # check if its a handle struct only, convert that into a distinct handle
    if len(obj["fields"]) == 1:
        field = obj["fields"][0]
        field_name = check_field_name(field["name"])

        if field_name == "h":
            file.write(f"{indent_str}{name} :: distinct u64")
            return

    seperator = " ::" if indent == 0 else ":"
    file.write(f"{indent_str}{name}{seperator} struct {{\n")
    gen_struct_fields(obj, file, indent + 1)
    file.write(f"{indent_str}}}")

# main object of the api which could be struct, union, enums or macros (unsupported)
def gen_typename_object(obj, file, indent):
    name = prefix_trim_oc(obj["name"])
    try_gen_doc(obj, file, indent)

    # try looking for a builtin match and leave early if written
    if gen_type_builtins(name, file, indent):
        return

    variable_type = obj["type"]
    kind = variable_type["kind"]

    if kind == "struct":
        gen_struct(variable_type, file, name, indent)
        
        # space out structs
        file.write("\n\n")
    elif kind == "union":
        print(f"union not done {name}")
        file.write(f"{name} :: union {{}}\n\n")
    elif kind == "enum":
        gen_enum(variable_type, file, name, indent)

# step through the main module objects
# procedures are written to a temp_block thats written once the module is stepped through
def iterate_object(obj, file, shared_block):
    if obj is None:
        return

    kind = obj["kind"]
    if kind == "module":
        gen_module_doc(obj, file)

    temp_block = io.StringIO("")

    if "contents" in obj:
        for child in obj["contents"]:
            iterate_object(child, file, temp_block)

    # finally write the procedures into the foreign block
    if kind == "module":
        module_size = temp_block.tell()

        # skip empty modules
        if module_size != 0:
            file.write(f"@(default_calling_convention=\"c\", link_prefix=\"oc_\")\nforeign {{\n")
            file.write(temp_block.getvalue())
            file.write("}\n\n")

        temp_block.seek(0)

    temp_block.close()

    if kind == "proc":
        gen_proc(obj, shared_block, 1)
    elif kind == "typename":
        gen_typename_object(obj, file, 0)

if __name__ == "__main__":
    with open("api.json", "r") as api_file:
        api_desc = json.load(api_file)

    with open("output.odin", "w") as odin_file:
        temp_block = io.StringIO("")
        
        for module in api_desc:
            iterate_object(module, odin_file, temp_block)
        
        temp_block.close()