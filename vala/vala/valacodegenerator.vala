/* valacodegenerator.vala
 *
 * Copyright (C) 2006-2007  Jürg Billeter, Raffaele Sandrini
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jürg Billeter <j@bitron.ch>
 *	Raffaele Sandrini <rasa@gmx.ch>
 */

using GLib;

/**
 * Code visitor generating C Code.
 */
public class Vala.CodeGenerator : CodeVisitor {
	/**
	 * Specifies whether automatic memory management is active.
	 */
	public bool memory_management { get; set; }
	
	private CodeContext context;
	
	Symbol root_symbol;
	Symbol current_symbol;
	Symbol current_type_symbol;
	Class current_class;
	TypeReference current_return_type;

	CCodeFragment header_begin;
	CCodeFragment header_type_declaration;
	CCodeFragment header_type_definition;
	CCodeFragment header_type_member_declaration;
	CCodeFragment source_begin;
	CCodeFragment source_include_directives;
	CCodeFragment source_type_member_declaration;
	CCodeFragment source_signal_marshaller_declaration;
	CCodeFragment source_type_member_definition;
	CCodeFragment instance_init_fragment;
	CCodeFragment instance_dispose_fragment;
	CCodeFragment source_signal_marshaller_definition;
	CCodeFragment module_init_fragment;
	
	CCodeStruct instance_struct;
	CCodeStruct type_struct;
	CCodeStruct instance_priv_struct;
	CCodeEnum prop_enum;
	CCodeEnum cenum;
	CCodeFunction function;
	CCodeBlock block;
	
	/* all temporary variables */
	List<VariableDeclarator> temp_vars;
	/* temporary variables that own their content */
	List<VariableDeclarator> temp_ref_vars;
	/* cache to check whether a certain marshaller has been created yet */
	HashTable<string,bool> user_marshal_list;
	/* (constant) hash table with all predefined marshallers */
	HashTable<string,bool> predefined_marshal_list;
	
	private int next_temp_var_id = 0;

	TypeReference bool_type;
	TypeReference char_type;
	TypeReference unichar_type;
	TypeReference short_type;
	TypeReference ushort_type;
	TypeReference int_type;
	TypeReference uint_type;
	TypeReference long_type;
	TypeReference ulong_type;
	TypeReference int64_type;
	TypeReference uint64_type;
	TypeReference string_type;
	TypeReference float_type;
	TypeReference double_type;
	DataType list_type;
	DataType slist_type;
	TypeReference mutex_type;
	DataType type_module_type;

	private bool in_plugin = false;
	private string module_init_param_name;

	public CodeGenerator (bool manage_memory = true) {
		memory_management = manage_memory;
	}
	
	construct {
		predefined_marshal_list = new HashTable (str_hash, str_equal);
		predefined_marshal_list.insert ("VOID:VOID", true);
		predefined_marshal_list.insert ("VOID:BOOLEAN", true);
		predefined_marshal_list.insert ("VOID:CHAR", true);
		predefined_marshal_list.insert ("VOID:UCHAR", true);
		predefined_marshal_list.insert ("VOID:INT", true);
		predefined_marshal_list.insert ("VOID:UINT", true);
		predefined_marshal_list.insert ("VOID:LONG", true);
		predefined_marshal_list.insert ("VOID:ULONG", true);
		predefined_marshal_list.insert ("VOID:ENUM", true);
		predefined_marshal_list.insert ("VOID:FLAGS", true);
		predefined_marshal_list.insert ("VOID:FLOAT", true);
		predefined_marshal_list.insert ("VOID:DOUBLE", true);
		predefined_marshal_list.insert ("VOID:STRING", true);
		predefined_marshal_list.insert ("VOID:POINTER", true);
		predefined_marshal_list.insert ("VOID:OBJECT", true);
		predefined_marshal_list.insert ("STRING:OBJECT,POINTER", true);
		predefined_marshal_list.insert ("VOID:UINT,POINTER", true);
		predefined_marshal_list.insert ("BOOLEAN:FLAGS", true);
	}

	/**
	 * Generate and emit C code for the specified code context.
	 *
	 * @param context a code context
	 */
	public void emit (CodeContext! context) {
		this.context = context;
	
		context.find_header_cycles ();

		root_symbol = context.get_root ();

		bool_type = new TypeReference ();
		bool_type.data_type = (DataType) root_symbol.lookup ("bool").node;

		char_type = new TypeReference ();
		char_type.data_type = (DataType) root_symbol.lookup ("char").node;

		unichar_type = new TypeReference ();
		unichar_type.data_type = (DataType) root_symbol.lookup ("unichar").node;

		short_type = new TypeReference ();
		short_type.data_type = (DataType) root_symbol.lookup ("short").node;
		
		ushort_type = new TypeReference ();
		ushort_type.data_type = (DataType) root_symbol.lookup ("ushort").node;

		int_type = new TypeReference ();
		int_type.data_type = (DataType) root_symbol.lookup ("int").node;
		
		uint_type = new TypeReference ();
		uint_type.data_type = (DataType) root_symbol.lookup ("uint").node;
		
		long_type = new TypeReference ();
		long_type.data_type = (DataType) root_symbol.lookup ("long").node;
		
		ulong_type = new TypeReference ();
		ulong_type.data_type = (DataType) root_symbol.lookup ("ulong").node;

		int64_type = new TypeReference ();
		int64_type.data_type = (DataType) root_symbol.lookup ("int64").node;
		
		uint64_type = new TypeReference ();
		uint64_type.data_type = (DataType) root_symbol.lookup ("uint64").node;
		
		float_type = new TypeReference ();
		float_type.data_type = (DataType) root_symbol.lookup ("float").node;

		double_type = new TypeReference ();
		double_type.data_type = (DataType) root_symbol.lookup ("double").node;

		string_type = new TypeReference ();
		string_type.data_type = (DataType) root_symbol.lookup ("string").node;

		var glib_ns = root_symbol.lookup ("GLib");
		
		list_type = (DataType) glib_ns.lookup ("List").node;
		slist_type = (DataType) glib_ns.lookup ("SList").node;
		
		mutex_type = new TypeReference ();
		mutex_type.data_type = (DataType) glib_ns.lookup ("Mutex").node;
		
		type_module_type = (DataType) glib_ns.lookup ("TypeModule").node;

		if (context.module_init_method != null) {
			module_init_fragment = new CCodeFragment ();
			foreach (FormalParameter parameter in context.module_init_method.get_parameters ()) {
				if (parameter.type_reference.data_type == type_module_type) {
					in_plugin = true;
					module_init_param_name = parameter.name;
					break;
				}
			}
		}
	
		/* we're only interested in non-pkg source files */
		var source_files = context.get_source_files ();
		foreach (SourceFile file in source_files) {
			if (!file.pkg) {
				file.accept (this);
			}
		}
	}
	
	private ref CCodeIncludeDirective get_internal_include (string! filename) {
		return new CCodeIncludeDirective (filename, context.library == null);
	}

	public override void visit_begin_source_file (SourceFile! source_file) {
		header_begin = new CCodeFragment ();
		header_type_declaration = new CCodeFragment ();
		header_type_definition = new CCodeFragment ();
		header_type_member_declaration = new CCodeFragment ();
		source_begin = new CCodeFragment ();
		source_include_directives = new CCodeFragment ();
		source_type_member_declaration = new CCodeFragment ();
		source_type_member_definition = new CCodeFragment ();
		source_signal_marshaller_definition = new CCodeFragment ();
		source_signal_marshaller_declaration = new CCodeFragment ();
		
		user_marshal_list = new HashTable (str_hash, str_equal);
		
		next_temp_var_id = 0;
		
		header_begin.append (new CCodeIncludeDirective ("glib.h"));
		header_begin.append (new CCodeIncludeDirective ("glib-object.h"));
		source_include_directives.append (new CCodeIncludeDirective (source_file.get_cheader_filename (), true));
		
		ref List<weak string> used_includes = null;
		used_includes.append ("glib.h");
		used_includes.append ("glib-object.h");
		used_includes.append (source_file.get_cheader_filename ());
		
		foreach (string filename1 in source_file.get_header_external_includes ()) {
			if (used_includes.find_custom (filename1, strcmp) == null) {
				header_begin.append (new CCodeIncludeDirective (filename1));
				used_includes.append (filename1);
			}
		}
		foreach (string filename2 in source_file.get_header_internal_includes ()) {
			if (used_includes.find_custom (filename2, strcmp) == null) {
				header_begin.append (get_internal_include (filename2));
				used_includes.append (filename2);
			}
		}
		foreach (string filename3 in source_file.get_source_external_includes ()) {
			if (used_includes.find_custom (filename3, strcmp) == null) {
				source_include_directives.append (new CCodeIncludeDirective (filename3));
				used_includes.append (filename3);
			}
		}
		foreach (string filename4 in source_file.get_source_internal_includes ()) {
			if (used_includes.find_custom (filename4, strcmp) == null) {
				source_include_directives.append (get_internal_include (filename4));
				used_includes.append (filename4);
			}
		}
		if (source_file.is_cycle_head) {
			foreach (SourceFile cycle_file in source_file.cycle.files) {
				var namespaces = cycle_file.get_namespaces ();
				foreach (Namespace ns in namespaces) {
					var structs = ns.get_structs ();
					foreach (Struct st in structs) {
						header_type_declaration.append (new CCodeTypeDefinition ("struct _%s".printf (st.get_cname ()), new CCodeVariableDeclarator (st.get_cname ())));
					}
					var classes = ns.get_classes ();
					foreach (Class cl in classes) {
						header_type_declaration.append (new CCodeTypeDefinition ("struct _%s".printf (cl.get_cname ()), new CCodeVariableDeclarator (cl.get_cname ())));
						header_type_declaration.append (new CCodeTypeDefinition ("struct _%sClass".printf (cl.get_cname ()), new CCodeVariableDeclarator ("%sClass".printf (cl.get_cname ()))));
					}
					var ifaces = ns.get_interfaces ();
					foreach (Interface iface in ifaces) {
						header_type_declaration.append (new CCodeTypeDefinition ("struct _%s".printf (iface.get_cname ()), new CCodeVariableDeclarator (iface.get_cname ())));
						header_type_declaration.append (new CCodeTypeDefinition ("struct _%s".printf (iface.get_type_cname ()), new CCodeVariableDeclarator (iface.get_type_cname ())));
					}
				}
			}
		}
		
		/* generate hardcoded "well-known" macros */
		source_begin.append (new CCodeMacroReplacement ("VALA_FREE_CHECKED(o,f)", "((o) == NULL ? NULL : ((o) = (f (o), NULL)))"));
		source_begin.append (new CCodeMacroReplacement ("VALA_FREE_UNCHECKED(o,f)", "((o) = (f (o), NULL))"));
	}
	
	private static ref string get_define_for_filename (string! filename) {
		var define = new String ("__");
		
		var i = filename;
		while (i.len () > 0) {
			var c = i.get_char ();
			if (c.isalnum  () && c < 0x80) {
				define.append_unichar (c.toupper ());
			} else {
				define.append_c ('_');
			}
		
			i = i.next_char ();
		}
		
		define.append ("__");
		
		return define.str;
	}
	
	public override void visit_end_source_file (SourceFile! source_file) {
		var header_define = get_define_for_filename (source_file.get_cheader_filename ());
		
		CCodeComment comment = null;
		if (source_file.comment != null) {
			comment = new CCodeComment (source_file.comment);
		}

		var writer = new CCodeWriter (source_file.get_cheader_filename ());
		if (comment != null) {
			comment.write (writer);
		}
		writer.write_newline ();
		var once = new CCodeOnceSection (header_define);
		once.append (new CCodeNewline ());
		once.append (header_begin);
		once.append (new CCodeNewline ());
		once.append (new CCodeIdentifier ("G_BEGIN_DECLS"));
		once.append (new CCodeNewline ());
		once.append (new CCodeNewline ());
		once.append (header_type_declaration);
		once.append (new CCodeNewline ());
		once.append (header_type_definition);
		once.append (new CCodeNewline ());
		once.append (header_type_member_declaration);
		once.append (new CCodeNewline ());
		once.append (new CCodeIdentifier ("G_END_DECLS"));
		once.append (new CCodeNewline ());
		once.append (new CCodeNewline ());
		once.write (writer);
		writer.close ();
		
		writer = new CCodeWriter (source_file.get_csource_filename ());
		if (comment != null) {
			comment.write (writer);
		}
		source_begin.write (writer);
		writer.write_newline ();
		source_include_directives.write (writer);
		writer.write_newline ();
		source_type_member_declaration.write (writer);
		writer.write_newline ();
		source_signal_marshaller_declaration.write (writer);
		writer.write_newline ();
		source_type_member_definition.write (writer);
		writer.write_newline ();
		source_signal_marshaller_definition.write (writer);
		writer.write_newline ();
		writer.close ();

		header_begin = null;
		header_type_declaration = null;
		header_type_definition = null;
		header_type_member_declaration = null;
		source_begin = null;
		source_include_directives = null;
		source_type_member_declaration = null;
		source_type_member_definition = null;
		source_signal_marshaller_definition = null;
		source_signal_marshaller_declaration = null;
	}

	public override void visit_begin_class (Class! cl) {
		current_symbol = cl.symbol;
		current_type_symbol = cl.symbol;
		current_class = cl;

		if (cl.is_static) {
			return;
		}

		instance_struct = new CCodeStruct ("_%s".printf (cl.get_cname ()));
		type_struct = new CCodeStruct ("_%sClass".printf (cl.get_cname ()));
		instance_priv_struct = new CCodeStruct ("_%sPrivate".printf (cl.get_cname ()));
		prop_enum = new CCodeEnum ();
		prop_enum.add_value ("%s_DUMMY_PROPERTY".printf (cl.get_upper_case_cname (null)), null);
		instance_init_fragment = new CCodeFragment ();
		instance_dispose_fragment = new CCodeFragment ();
		
		
		header_type_declaration.append (new CCodeNewline ());
		var macro = "(%s_get_type ())".printf (cl.get_lower_case_cname (null));
		header_type_declaration.append (new CCodeMacroReplacement (cl.get_upper_case_cname ("TYPE_"), macro));

		macro = "(G_TYPE_CHECK_INSTANCE_CAST ((obj), %s, %s))".printf (cl.get_upper_case_cname ("TYPE_"), cl.get_cname ());
		header_type_declaration.append (new CCodeMacroReplacement ("%s(obj)".printf (cl.get_upper_case_cname (null)), macro));

		macro = "(G_TYPE_CHECK_CLASS_CAST ((klass), %s, %sClass))".printf (cl.get_upper_case_cname ("TYPE_"), cl.get_cname ());
		header_type_declaration.append (new CCodeMacroReplacement ("%s_CLASS(klass)".printf (cl.get_upper_case_cname (null)), macro));

		macro = "(G_TYPE_CHECK_INSTANCE_TYPE ((obj), %s))".printf (cl.get_upper_case_cname ("TYPE_"));
		header_type_declaration.append (new CCodeMacroReplacement ("%s(obj)".printf (cl.get_upper_case_cname ("IS_")), macro));

		macro = "(G_TYPE_CHECK_CLASS_TYPE ((klass), %s))".printf (cl.get_upper_case_cname ("TYPE_"));
		header_type_declaration.append (new CCodeMacroReplacement ("%s_CLASS(klass)".printf (cl.get_upper_case_cname ("IS_")), macro));

		macro = "(G_TYPE_INSTANCE_GET_CLASS ((obj), %s, %sClass))".printf (cl.get_upper_case_cname ("TYPE_"), cl.get_cname ());
		header_type_declaration.append (new CCodeMacroReplacement ("%s_GET_CLASS(obj)".printf (cl.get_upper_case_cname (null)), macro));
		header_type_declaration.append (new CCodeNewline ());


		if (cl.source_reference.file.cycle == null) {
			header_type_declaration.append (new CCodeTypeDefinition ("struct %s".printf (instance_struct.name), new CCodeVariableDeclarator (cl.get_cname ())));
			header_type_declaration.append (new CCodeTypeDefinition ("struct %s".printf (type_struct.name), new CCodeVariableDeclarator ("%sClass".printf (cl.get_cname ()))));
		}
		header_type_declaration.append (new CCodeTypeDefinition ("struct %s".printf (instance_priv_struct.name), new CCodeVariableDeclarator ("%sPrivate".printf (cl.get_cname ()))));
		
		instance_struct.add_field (cl.base_class.get_cname (), "parent");
		instance_struct.add_field ("%sPrivate *".printf (cl.get_cname ()), "priv");
		type_struct.add_field ("%sClass".printf (cl.base_class.get_cname ()), "parent");

		if (cl.source_reference.comment != null) {
			header_type_definition.append (new CCodeComment (cl.source_reference.comment));
		}
		header_type_definition.append (instance_struct);
		header_type_definition.append (type_struct);
		source_type_member_declaration.append (instance_priv_struct);
		macro = "(G_TYPE_INSTANCE_GET_PRIVATE ((o), %s, %sPrivate))".printf (cl.get_upper_case_cname ("TYPE_"), cl.get_cname ());
		source_type_member_declaration.append (new CCodeMacroReplacement ("%s_GET_PRIVATE(o)".printf (cl.get_upper_case_cname (null)), macro));
		source_type_member_declaration.append (prop_enum);
	}
	
	public override void visit_end_class (Class! cl) {
		if (!cl.is_static) {
			add_get_property_function (cl);
			add_set_property_function (cl);
			add_class_init_function (cl);
			
			foreach (TypeReference base_type in cl.get_base_types ()) {
				if (base_type.data_type is Interface) {
					add_interface_init_function (cl, (Interface) base_type.data_type);
				}
			}
			
			add_instance_init_function (cl);
			if (memory_management && cl.get_fields () != null) {
				add_dispose_function (cl);
			}
			
			var type_fun = new ClassRegisterFunction (cl);
			type_fun.init_from_type (in_plugin);
			header_type_member_declaration.append (type_fun.get_declaration ());
			source_type_member_definition.append (type_fun.get_definition ());
			
			if (in_plugin) {
				// FIXME resolve potential dependency issues, i.e. base types have to be registered before derived types
				var register_call = new CCodeFunctionCall (new CCodeIdentifier ("%s_register_type".printf (cl.get_lower_case_cname (null))));
				register_call.add_argument (new CCodeIdentifier (module_init_param_name));
				module_init_fragment.append (new CCodeExpressionStatement (register_call));
			}
		}

		current_type_symbol = null;
		current_class = null;
		instance_dispose_fragment = null;
	}
	
	private void add_class_init_function (Class! cl) {
		var class_init = new CCodeFunction ("%s_class_init".printf (cl.get_lower_case_cname (null)), "void");
		class_init.add_parameter (new CCodeFormalParameter ("klass", "%sClass *".printf (cl.get_cname ())));
		class_init.modifiers = CCodeModifiers.STATIC;
		
		var init_block = new CCodeBlock ();
		class_init.block = init_block;
		
		ref CCodeFunctionCall ccall;
		
		/* save pointer to parent class */
		var parent_decl = new CCodeDeclaration ("gpointer");
		var parent_var_decl = new CCodeVariableDeclarator ("%s_parent_class".printf (cl.get_lower_case_cname (null)));
		parent_var_decl.initializer = new CCodeConstant ("NULL");
		parent_decl.add_declarator (parent_var_decl);
		parent_decl.modifiers = CCodeModifiers.STATIC;
		source_type_member_declaration.append (parent_decl);
		ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_class_peek_parent"));
		ccall.add_argument (new CCodeIdentifier ("klass"));
		var parent_assignment = new CCodeAssignment (new CCodeIdentifier ("%s_parent_class".printf (cl.get_lower_case_cname (null))), ccall);
		init_block.add_statement (new CCodeExpressionStatement (parent_assignment));
		
		/* add struct for private fields */
		if (cl.has_private_fields) {
			ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_class_add_private"));
			ccall.add_argument (new CCodeIdentifier ("klass"));
			ccall.add_argument (new CCodeConstant ("sizeof (%sPrivate)".printf (cl.get_cname ())));
			init_block.add_statement (new CCodeExpressionStatement (ccall));
		}
		
		/* set property handlers */
		ccall = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT_CLASS"));
		ccall.add_argument (new CCodeIdentifier ("klass"));
		init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (ccall, "get_property"), new CCodeIdentifier ("%s_get_property".printf (cl.get_lower_case_cname (null))))));
		init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (ccall, "set_property"), new CCodeIdentifier ("%s_set_property".printf (cl.get_lower_case_cname (null))))));
		
		/* set constructor */
		if (cl.constructor != null) {
			var ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT_CLASS"));
			ccast.add_argument (new CCodeIdentifier ("klass"));
			init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (ccast, "constructor"), new CCodeIdentifier ("%s_constructor".printf (cl.get_lower_case_cname (null))))));
		}

		/* set dispose function */
		if (memory_management && cl.get_fields () != null) {
			var ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT_CLASS"));
			ccast.add_argument (new CCodeIdentifier ("klass"));
			init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (ccast, "dispose"), new CCodeIdentifier ("%s_dispose".printf (cl.get_lower_case_cname (null))))));
		}
		
		/* connect overridden methods */
		var methods = cl.get_methods ();
		foreach (Method m in methods) {
			if (m.base_method == null) {
				continue;
			}
			var base_type = m.base_method.symbol.parent_symbol.node;
			
			var ccast = new CCodeFunctionCall (new CCodeIdentifier ("%s_CLASS".printf (((Class) base_type).get_upper_case_cname (null))));
			ccast.add_argument (new CCodeIdentifier ("klass"));
			init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (ccast, m.name), new CCodeIdentifier (m.get_real_cname ()))));
		}
		
		/* create properties */
		var props = cl.get_properties ();
		foreach (Property prop in props) {
			if (prop.base_property != null || prop.base_interface_property != null) {
				var cinst = new CCodeFunctionCall (new CCodeIdentifier ("g_object_class_override_property"));
				cinst.add_argument (ccall);
				cinst.add_argument (new CCodeConstant (prop.get_upper_case_cname ()));
				cinst.add_argument (prop.get_canonical_cconstant ());
				
				init_block.add_statement (new CCodeExpressionStatement (cinst));
			} else {
				var cinst = new CCodeFunctionCall (new CCodeIdentifier ("g_object_class_install_property"));
				cinst.add_argument (ccall);
				cinst.add_argument (new CCodeConstant (prop.get_upper_case_cname ()));
				cinst.add_argument (get_param_spec (prop));
				
				init_block.add_statement (new CCodeExpressionStatement (cinst));
			}
		}
		
		/* create signals */
		foreach (Signal sig in cl.get_signals ()) {
			init_block.add_statement (new CCodeExpressionStatement (get_signal_creation (sig, cl)));
		}
		
		source_type_member_definition.append (class_init);
	}
	
	private void add_interface_init_function (Class! cl, Interface! iface) {
		var iface_init = new CCodeFunction ("%s_%s_interface_init".printf (cl.get_lower_case_cname (null), iface.get_lower_case_cname (null)), "void");
		iface_init.add_parameter (new CCodeFormalParameter ("iface", "%s *".printf (iface.get_type_cname ())));
		iface_init.modifiers = CCodeModifiers.STATIC;
		
		var init_block = new CCodeBlock ();
		iface_init.block = init_block;
		
		ref CCodeFunctionCall ccall;
		
		/* save pointer to parent vtable */
		string parent_iface_var = "%s_%s_parent_iface".printf (cl.get_lower_case_cname (null), iface.get_lower_case_cname (null));
		var parent_decl = new CCodeDeclaration (iface.get_type_cname () + "*");
		var parent_var_decl = new CCodeVariableDeclarator (parent_iface_var);
		parent_var_decl.initializer = new CCodeConstant ("NULL");
		parent_decl.add_declarator (parent_var_decl);
		parent_decl.modifiers = CCodeModifiers.STATIC;
		source_type_member_declaration.append (parent_decl);
		ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_interface_peek_parent"));
		ccall.add_argument (new CCodeIdentifier ("iface"));
		var parent_assignment = new CCodeAssignment (new CCodeIdentifier (parent_iface_var), ccall);
		init_block.add_statement (new CCodeExpressionStatement (parent_assignment));

		var methods = cl.get_methods ();
		foreach (Method m in methods) {
			if (m.base_interface_method == null) {
				continue;
			}

			var base_type = m.base_interface_method.symbol.parent_symbol.node;
			if (base_type != iface) {
				continue;
			}
			
			var ciface = new CCodeIdentifier ("iface");
			init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (ciface, m.name), new CCodeIdentifier (m.get_real_cname ()))));
		}
		
		source_type_member_definition.append (iface_init);
	}
	
	private void add_instance_init_function (Class! cl) {
		var instance_init = new CCodeFunction ("%s_init".printf (cl.get_lower_case_cname (null)), "void");
		instance_init.add_parameter (new CCodeFormalParameter ("self", "%s *".printf (cl.get_cname ())));
		instance_init.modifiers = CCodeModifiers.STATIC;
		
		var init_block = new CCodeBlock ();
		instance_init.block = init_block;
		
		if (cl.has_private_fields) {
			var ccall = new CCodeFunctionCall (new CCodeIdentifier ("%s_GET_PRIVATE".printf (cl.get_upper_case_cname (null))));
			ccall.add_argument (new CCodeIdentifier ("self"));
			init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), "priv"), ccall)));
		}
		
		init_block.add_statement (instance_init_fragment);
		
		var init_sym = cl.symbol.lookup ("init");
		if (init_sym != null) {
			var init_fun = (Method) init_sym.node;
			init_block.add_statement (init_fun.body.ccodenode);
		}
		
		source_type_member_definition.append (instance_init);
	}
	
	private void add_dispose_function (Class! cl) {
		function = new CCodeFunction ("%s_dispose".printf (cl.get_lower_case_cname (null)), "void");
		function.modifiers = CCodeModifiers.STATIC;
		
		function.add_parameter (new CCodeFormalParameter ("obj", "GObject *"));
		
		source_type_member_declaration.append (function.copy ());


		var cblock = new CCodeBlock ();

		var ccall = new CCodeFunctionCall (new CCodeIdentifier (cl.get_upper_case_cname (null)));
		ccall.add_argument (new CCodeIdentifier ("obj"));
		
		var cdecl = new CCodeDeclaration ("%s *".printf (cl.get_cname ()));
		cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("self", ccall));
		
		cblock.add_statement (cdecl);
		
		cblock.add_statement (instance_dispose_fragment);

		cdecl = new CCodeDeclaration ("%sClass *".printf (cl.get_cname ()));
		cdecl.add_declarator (new CCodeVariableDeclarator ("klass"));
		cblock.add_statement (cdecl);

		cdecl = new CCodeDeclaration ("GObjectClass *");
		cdecl.add_declarator (new CCodeVariableDeclarator ("parent_class"));
		cblock.add_statement (cdecl);


		ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_class_peek"));
		ccall.add_argument (new CCodeIdentifier (cl.get_upper_case_cname ("TYPE_")));
		var ccast = new CCodeFunctionCall (new CCodeIdentifier ("%s_CLASS".printf (cl.get_upper_case_cname (null))));
		ccast.add_argument (ccall);
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("klass"), ccast)));

		ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_class_peek_parent"));
		ccall.add_argument (new CCodeIdentifier ("klass"));
		ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT_CLASS"));
		ccast.add_argument (ccall);
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("parent_class"), ccast)));

		
		ccall = new CCodeFunctionCall (new CCodeMemberAccess.pointer (new CCodeIdentifier ("parent_class"), "dispose"));
		ccall.add_argument (new CCodeIdentifier ("obj"));
		cblock.add_statement (new CCodeExpressionStatement (ccall));


		function.block = cblock;

		source_type_member_definition.append (function);
	}
	
	private ref CCodeIdentifier! get_value_setter_function (TypeReference! type_reference) {
		if (type_reference.data_type is Class || type_reference.data_type is Interface) {
			return new CCodeIdentifier ("g_value_set_object");
		} else if (type_reference.data_type == string_type.data_type) {
			return new CCodeIdentifier ("g_value_set_string");
		} else if (type_reference.data_type == int_type.data_type
			   || type_reference.data_type is Enum) {
			return new CCodeIdentifier ("g_value_set_int");
		} else if (type_reference.data_type == uint_type.data_type) {
			return new CCodeIdentifier ("g_value_set_uint");
		} else if (type_reference.data_type == long_type.data_type) {
			return new CCodeIdentifier ("g_value_set_long");
		} else if (type_reference.data_type == ulong_type.data_type) {
			return new CCodeIdentifier ("g_value_set_ulong");
		} else if (type_reference.data_type == bool_type.data_type) {
			return new CCodeIdentifier ("g_value_set_boolean");
		} else if (type_reference.data_type == float_type.data_type) {
			return new CCodeIdentifier ("g_value_set_float");
		} else if (type_reference.data_type == double_type.data_type) {
			return new CCodeIdentifier ("g_value_set_double");
		} else {
			return new CCodeIdentifier ("g_value_set_pointer");
		}
	}
	
	private void add_get_property_function (Class! cl) {
		var get_prop = new CCodeFunction ("%s_get_property".printf (cl.get_lower_case_cname (null)), "void");
		get_prop.modifiers = CCodeModifiers.STATIC;
		get_prop.add_parameter (new CCodeFormalParameter ("object", "GObject *"));
		get_prop.add_parameter (new CCodeFormalParameter ("property_id", "guint"));
		get_prop.add_parameter (new CCodeFormalParameter ("value", "GValue *"));
		get_prop.add_parameter (new CCodeFormalParameter ("pspec", "GParamSpec *"));
		
		var block = new CCodeBlock ();
		
		var ccall = new CCodeFunctionCall (new CCodeIdentifier (cl.get_upper_case_cname (null)));
		ccall.add_argument (new CCodeIdentifier ("object"));
		var cdecl = new CCodeDeclaration ("%s *".printf (cl.get_cname ()));
		cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("self", ccall));
		block.add_statement (cdecl);
		
		var cswitch = new CCodeSwitchStatement (new CCodeIdentifier ("property_id"));
		var props = cl.get_properties ();
		foreach (Property prop in props) {
			if (prop.get_accessor == null) {
				continue;
			}

			bool is_virtual = prop.base_property != null || prop.base_interface_property != null;

			string prefix = cl.get_lower_case_cname (null);
			if (is_virtual) {
				prefix += "_real";
			}

			var ccase = new CCodeCaseStatement (new CCodeIdentifier (prop.get_upper_case_cname ()));
			var ccall = new CCodeFunctionCall (new CCodeIdentifier ("%s_get_%s".printf (prefix, prop.name)));
			ccall.add_argument (new CCodeIdentifier ("self"));
			var csetcall = new CCodeFunctionCall ();
			csetcall.call = get_value_setter_function (prop.type_reference);
			csetcall.add_argument (new CCodeIdentifier ("value"));
			csetcall.add_argument (ccall);
			ccase.add_statement (new CCodeExpressionStatement (csetcall));
			ccase.add_statement (new CCodeBreakStatement ());
			cswitch.add_case (ccase);
		}
		block.add_statement (cswitch);

		get_prop.block = block;
		
		source_type_member_definition.append (get_prop);
	}
	
	private void add_set_property_function (Class! cl) {
		var set_prop = new CCodeFunction ("%s_set_property".printf (cl.get_lower_case_cname (null)), "void");
		set_prop.modifiers = CCodeModifiers.STATIC;
		set_prop.add_parameter (new CCodeFormalParameter ("object", "GObject *"));
		set_prop.add_parameter (new CCodeFormalParameter ("property_id", "guint"));
		set_prop.add_parameter (new CCodeFormalParameter ("value", "const GValue *"));
		set_prop.add_parameter (new CCodeFormalParameter ("pspec", "GParamSpec *"));
		
		var block = new CCodeBlock ();
		
		var ccall = new CCodeFunctionCall (new CCodeIdentifier (cl.get_upper_case_cname (null)));
		ccall.add_argument (new CCodeIdentifier ("object"));
		var cdecl = new CCodeDeclaration ("%s *".printf (cl.get_cname ()));
		cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("self", ccall));
		block.add_statement (cdecl);
		
		var cswitch = new CCodeSwitchStatement (new CCodeIdentifier ("property_id"));
		var props = cl.get_properties ();
		foreach (Property prop in props) {
			if (prop.set_accessor == null) {
				continue;
			}

			bool is_virtual = prop.base_property != null || prop.base_interface_property != null;

			string prefix = cl.get_lower_case_cname (null);
			if (is_virtual) {
				prefix += "_real";
			}

			var ccase = new CCodeCaseStatement (new CCodeIdentifier (prop.get_upper_case_cname ()));
			var ccall = new CCodeFunctionCall (new CCodeIdentifier ("%s_set_%s".printf (prefix, prop.name)));
			ccall.add_argument (new CCodeIdentifier ("self"));
			var cgetcall = new CCodeFunctionCall ();
			if (prop.type_reference.data_type is Class || prop.type_reference.data_type is Interface) {
				cgetcall.call = new CCodeIdentifier ("g_value_get_object");
			} else if (prop.type_reference.type_name == "string") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_string");
			} else if (prop.type_reference.type_name == "int" || prop.type_reference.data_type is Enum) {
				cgetcall.call = new CCodeIdentifier ("g_value_get_int");
			} else if (prop.type_reference.type_name == "uint") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_uint");
			} else if (prop.type_reference.type_name == "long") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_long");
			} else if (prop.type_reference.type_name == "ulong") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_ulong");
			} else if (prop.type_reference.type_name == "bool") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_boolean");
			} else if (prop.type_reference.type_name == "float") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_float");
			} else if (prop.type_reference.type_name == "double") {
				cgetcall.call = new CCodeIdentifier ("g_value_get_double");
			} else {
				cgetcall.call = new CCodeIdentifier ("g_value_get_pointer");
			}
			cgetcall.add_argument (new CCodeIdentifier ("value"));
			ccall.add_argument (cgetcall);
			ccase.add_statement (new CCodeExpressionStatement (ccall));
			ccase.add_statement (new CCodeBreakStatement ());
			cswitch.add_case (ccase);
		}
		block.add_statement (cswitch);
		
		set_prop.block = block;
		
		source_type_member_definition.append (set_prop);
	}
	
	public override void visit_begin_struct (Struct! st) {
		current_type_symbol = st.symbol;

		instance_struct = new CCodeStruct ("_%s".printf (st.get_cname ()));

		if (st.source_reference.file.cycle == null) {
			header_type_declaration.append (new CCodeTypeDefinition ("struct _%s".printf (st.get_cname ()), new CCodeVariableDeclarator (st.get_cname ())));
		}

		if (st.source_reference.comment != null) {
			header_type_definition.append (new CCodeComment (st.source_reference.comment));
		}
		header_type_definition.append (instance_struct);
	}
	
	public override void visit_end_struct (Struct! st) {
		current_type_symbol = null;
	}

	public override void visit_begin_interface (Interface! iface) {
		current_symbol = iface.symbol;
		current_type_symbol = iface.symbol;

		type_struct = new CCodeStruct ("_%s".printf (iface.get_type_cname ()));
		
		header_type_declaration.append (new CCodeNewline ());
		var macro = "(%s_get_type ())".printf (iface.get_lower_case_cname (null));
		header_type_declaration.append (new CCodeMacroReplacement (iface.get_upper_case_cname ("TYPE_"), macro));

		macro = "(G_TYPE_CHECK_INSTANCE_CAST ((obj), %s, %s))".printf (iface.get_upper_case_cname ("TYPE_"), iface.get_cname ());
		header_type_declaration.append (new CCodeMacroReplacement ("%s(obj)".printf (iface.get_upper_case_cname (null)), macro));

		macro = "(G_TYPE_CHECK_INSTANCE_TYPE ((obj), %s))".printf (iface.get_upper_case_cname ("TYPE_"));
		header_type_declaration.append (new CCodeMacroReplacement ("%s(obj)".printf (iface.get_upper_case_cname ("IS_")), macro));

		macro = "(G_TYPE_INSTANCE_GET_INTERFACE ((obj), %s, %s))".printf (iface.get_upper_case_cname ("TYPE_"), iface.get_type_cname ());
		header_type_declaration.append (new CCodeMacroReplacement ("%s_GET_INTERFACE(obj)".printf (iface.get_upper_case_cname (null)), macro));
		header_type_declaration.append (new CCodeNewline ());


		if (iface.source_reference.file.cycle == null) {
			header_type_declaration.append (new CCodeTypeDefinition ("struct _%s".printf (iface.get_cname ()), new CCodeVariableDeclarator (iface.get_cname ())));
			header_type_declaration.append (new CCodeTypeDefinition ("struct %s".printf (type_struct.name), new CCodeVariableDeclarator (iface.get_type_cname ())));
		}
		
		type_struct.add_field ("GTypeInterface", "parent");

		if (iface.source_reference.comment != null) {
			header_type_definition.append (new CCodeComment (iface.source_reference.comment));
		}
		header_type_definition.append (type_struct);
	}

	public override void visit_end_interface (Interface! iface) {
		add_interface_base_init_function (iface);

		var type_fun = new InterfaceRegisterFunction (iface);
		type_fun.init_from_type ();
		header_type_member_declaration.append (type_fun.get_declaration ());
		source_type_member_definition.append (type_fun.get_definition ());

		current_type_symbol = null;
	}
	
	private ref CCodeFunctionCall! get_param_spec (Property! prop) {
		var cspec = new CCodeFunctionCall ();
		cspec.add_argument (prop.get_canonical_cconstant ());
		cspec.add_argument (new CCodeConstant ("\"foo\""));
		cspec.add_argument (new CCodeConstant ("\"bar\""));
		if (prop.type_reference.data_type is Class || prop.type_reference.data_type is Interface) {
			cspec.call = new CCodeIdentifier ("g_param_spec_object");
			cspec.add_argument (new CCodeIdentifier (prop.type_reference.data_type.get_upper_case_cname ("TYPE_")));
		} else if (prop.type_reference.data_type == string_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_string");
			cspec.add_argument (new CCodeConstant ("NULL"));
		} else if (prop.type_reference.data_type == int_type.data_type
			   || prop.type_reference.data_type is Enum) {
			cspec.call = new CCodeIdentifier ("g_param_spec_int");
			cspec.add_argument (new CCodeConstant ("G_MININT"));
			cspec.add_argument (new CCodeConstant ("G_MAXINT"));
			cspec.add_argument (new CCodeConstant ("0"));
		} else if (prop.type_reference.data_type == uint_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_uint");
			cspec.add_argument (new CCodeConstant ("0"));
			cspec.add_argument (new CCodeConstant ("G_MAXUINT"));
			cspec.add_argument (new CCodeConstant ("0"));
		} else if (prop.type_reference.data_type == long_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_long");
			cspec.add_argument (new CCodeConstant ("G_MINLONG"));
			cspec.add_argument (new CCodeConstant ("G_MAXLONG"));
			cspec.add_argument (new CCodeConstant ("0"));
		} else if (prop.type_reference.data_type == ulong_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_ulong");
			cspec.add_argument (new CCodeConstant ("0"));
			cspec.add_argument (new CCodeConstant ("G_MAXULONG"));
			cspec.add_argument (new CCodeConstant ("0"));
		} else if (prop.type_reference.data_type == bool_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_boolean");
			cspec.add_argument (new CCodeConstant ("FALSE"));
		} else if (prop.type_reference.data_type == float_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_float");
			cspec.add_argument (new CCodeConstant ("-G_MAXFLOAT"));
			cspec.add_argument (new CCodeConstant ("G_MAXFLOAT"));
			cspec.add_argument (new CCodeConstant ("0"));
		} else if (prop.type_reference.data_type == double_type.data_type) {
			cspec.call = new CCodeIdentifier ("g_param_spec_double");
			cspec.add_argument (new CCodeConstant ("-G_MAXDOUBLE"));
			cspec.add_argument (new CCodeConstant ("G_MAXDOUBLE"));
			cspec.add_argument (new CCodeConstant ("0"));
		} else {
			cspec.call = new CCodeIdentifier ("g_param_spec_pointer");
		}
		
		var pflags = "G_PARAM_STATIC_NAME | G_PARAM_STATIC_NICK | G_PARAM_STATIC_BLURB";
		if (prop.get_accessor != null) {
			pflags = "%s%s".printf (pflags, " | G_PARAM_READABLE");
		}
		if (prop.set_accessor != null) {
			pflags = "%s%s".printf (pflags, " | G_PARAM_WRITABLE");
			if (prop.set_accessor.construction) {
				if (prop.set_accessor.writable) {
					pflags = "%s%s".printf (pflags, " | G_PARAM_CONSTRUCT");
				} else {
					pflags = "%s%s".printf (pflags, " | G_PARAM_CONSTRUCT_ONLY");
				}
			}
		}
		cspec.add_argument (new CCodeConstant (pflags));

		return cspec;
	}

	private ref CCodeFunctionCall! get_signal_creation (Signal! sig, DataType! type) {	
		var csignew = new CCodeFunctionCall (new CCodeIdentifier ("g_signal_new"));
		csignew.add_argument (new CCodeConstant ("\"%s\"".printf (sig.name)));
		csignew.add_argument (new CCodeIdentifier (type.get_upper_case_cname ("TYPE_")));
		csignew.add_argument (new CCodeConstant ("G_SIGNAL_RUN_LAST"));
		csignew.add_argument (new CCodeConstant ("0"));
		csignew.add_argument (new CCodeConstant ("NULL"));
		csignew.add_argument (new CCodeConstant ("NULL"));

		string marshaller = get_signal_marshaller_function (sig);

		var marshal_arg = new CCodeIdentifier (marshaller);
		csignew.add_argument (marshal_arg);

		var params = sig.get_parameters ();
		var params_len = params.length ();
		if (sig.return_type.type_parameter != null) {
			csignew.add_argument (new CCodeConstant ("G_TYPE_POINTER"));
		} else if (sig.return_type.data_type == null) {
			csignew.add_argument (new CCodeConstant ("G_TYPE_NONE"));
		} else {
			csignew.add_argument (new CCodeConstant (sig.return_type.data_type.get_type_id ()));
		}
		csignew.add_argument (new CCodeConstant ("%d".printf (params_len)));
		foreach (FormalParameter param in params) {
			if (param.type_reference.type_parameter != null) {
				csignew.add_argument (new CCodeConstant ("G_TYPE_POINTER"));
			} else {
				csignew.add_argument (new CCodeConstant (param.type_reference.data_type.get_type_id ()));
			}
		}

		marshal_arg.name = marshaller;

		return csignew;
	}

	private void add_interface_base_init_function (Interface! iface) {
		var base_init = new CCodeFunction ("%s_base_init".printf (iface.get_lower_case_cname (null)), "void");
		base_init.add_parameter (new CCodeFormalParameter ("iface", "%sIface *".printf (iface.get_cname ())));
		base_init.modifiers = CCodeModifiers.STATIC;
		
		var init_block = new CCodeBlock ();
		
		/* make sure not to run the initialization code twice */
		base_init.block = new CCodeBlock ();
		var decl = new CCodeDeclaration (bool_type.get_cname ());
		decl.modifiers |= CCodeModifiers.STATIC;
		decl.add_declarator (new CCodeVariableDeclarator.with_initializer ("initialized", new CCodeConstant ("FALSE")));
		base_init.block.add_statement (decl);
		var cif = new CCodeIfStatement (new CCodeUnaryExpression (CCodeUnaryOperator.LOGICAL_NEGATION, new CCodeIdentifier ("initialized")), init_block);
		base_init.block.add_statement (cif);
		init_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("initialized"), new CCodeConstant ("TRUE"))));
		
		/* create properties */
		var props = iface.get_properties ();
		foreach (Property prop in props) {
			var cinst = new CCodeFunctionCall (new CCodeIdentifier ("g_object_interface_install_property"));
			cinst.add_argument (new CCodeIdentifier ("iface"));
			cinst.add_argument (get_param_spec (prop));

			init_block.add_statement (new CCodeExpressionStatement (cinst));
		}
		
		/* create signals */
		foreach (Signal sig in iface.get_signals ()) {
			init_block.add_statement (new CCodeExpressionStatement (get_signal_creation (sig, iface)));
		}
		
		source_type_member_definition.append (base_init);
	}
	
	public override void visit_begin_enum (Enum! en) {
		cenum = new CCodeEnum (en.get_cname ());

		if (en.source_reference.comment != null) {
			header_type_definition.append (new CCodeComment (en.source_reference.comment));
		}
		header_type_definition.append (cenum);
	}

	public override void visit_enum_value (EnumValue! ev) {
		string val;
		if (ev.value is LiteralExpression) {
			var lit = ((LiteralExpression) ev.value).literal;
			if (lit is IntegerLiteral) {
				val = ((IntegerLiteral) lit).value;
			}
		}
		cenum.add_value (ev.get_cname (), val);
	}

	public override void visit_end_callback (Callback! cb) {
		var cfundecl = new CCodeFunctionDeclarator (cb.get_cname ());
		foreach (FormalParameter param in cb.get_parameters ()) {
			cfundecl.add_parameter ((CCodeFormalParameter) param.ccodenode);
		}
		
		var ctypedef = new CCodeTypeDefinition (cb.return_type.get_cname (), cfundecl);
		
		if (cb.access != MemberAccessibility.PRIVATE) {
			header_type_declaration.append (ctypedef);
		} else {
			source_type_member_declaration.append (ctypedef);
		}
	}
	
	public override void visit_member (Member! m) {
		/* stuff meant for all lockable members */
		if (m is Lockable && ((Lockable)m).get_lock_used ()) {
			instance_priv_struct.add_field (mutex_type.get_cname (), get_symbol_lock_name (m.symbol));
			
			instance_init_fragment.append (
				new CCodeExpressionStatement (
					new CCodeAssignment (
						new CCodeMemberAccess.pointer (
							new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), "priv"),
							get_symbol_lock_name (m.symbol)),
					new CCodeFunctionCall (new CCodeIdentifier (((Struct)mutex_type.data_type).default_construction_method.get_cname ())))));
			
			var fc = new CCodeFunctionCall (new CCodeIdentifier ("VALA_FREE_CHECKED"));
			fc.add_argument (
				new CCodeMemberAccess.pointer (
					new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), "priv"),
					get_symbol_lock_name (m.symbol)));
			fc.add_argument (new CCodeIdentifier (mutex_type.data_type.get_free_function ()));
			if (instance_dispose_fragment != null) {
				instance_dispose_fragment.append (new CCodeExpressionStatement (fc));
			}
		}
	}

	public override void visit_constant (Constant! c) {
		if (c.symbol.parent_symbol.node is DataType) {
			var t = (DataType) c.symbol.parent_symbol.node;
			var cdecl = new CCodeDeclaration (c.type_reference.get_const_cname ());
			var arr = "";
			if (c.type_reference.data_type is Array) {
				arr = "[]";
			}
			cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("%s%s".printf (c.get_cname (), arr), (CCodeExpression) c.initializer.ccodenode));
			cdecl.modifiers = CCodeModifiers.STATIC;
			
			if (c.access != MemberAccessibility.PRIVATE) {
				header_type_member_declaration.append (cdecl);
			} else {
				source_type_member_declaration.append (cdecl);
			}
		}
	}
	
	public override void visit_field (Field! f) {
		CCodeExpression lhs = null;
		CCodeStruct st = null;
		
		if (f.access != MemberAccessibility.PRIVATE) {
			st = instance_struct;
			if (f.instance) {
				lhs = new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), f.get_cname ());
			}
		} else if (f.access == MemberAccessibility.PRIVATE) {
			if (f.instance) {
				st = instance_priv_struct;
				lhs = new CCodeMemberAccess.pointer (new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), "priv"), f.get_cname ());
			} else {
				if (f.symbol.parent_symbol.node is DataType) {
					var t = (DataType) f.symbol.parent_symbol.node;
					var cdecl = new CCodeDeclaration (f.type_reference.get_cname ());
					var var_decl = new CCodeVariableDeclarator (f.get_cname ());
					if (f.initializer != null) {
						var_decl.initializer = (CCodeExpression) f.initializer.ccodenode;
					}
					cdecl.add_declarator (var_decl);
					cdecl.modifiers = CCodeModifiers.STATIC;
					source_type_member_declaration.append (cdecl);
				}
			}
		}

		if (f.instance)  {
			st.add_field (f.type_reference.get_cname (), f.get_cname ());
			if (f.type_reference.data_type is Array && !f.no_array_length) {
				// create fields to store array dimensions
				var arr = (Array) f.type_reference.data_type;
				
				for (int dim = 1; dim <= arr.rank; dim++) {
					var len_type = new TypeReference ();
					len_type.data_type = int_type.data_type;

					st.add_field (len_type.get_cname (), get_array_length_cname (f.name, dim));
				}
			}

			if (f.initializer != null) {
				instance_init_fragment.append (new CCodeExpressionStatement (new CCodeAssignment (lhs, (CCodeExpression) f.initializer.ccodenode)));
				
				if (f.type_reference.data_type is Array && !f.no_array_length &&
				    f.initializer is ArrayCreationExpression) {
					var ma = new MemberAccess.simple (f.name);
					ma.symbol_reference = f.symbol;
					
					var array_len_lhs = get_array_length_cexpression (ma, 1);
					var sizes = ((ArrayCreationExpression) f.initializer).get_sizes ();
					var size = (Expression) sizes.data;
					instance_init_fragment.append (new CCodeExpressionStatement (new CCodeAssignment (array_len_lhs, (CCodeExpression) size.ccodenode)));
				}
			}
			
			if (f.type_reference.takes_ownership && instance_dispose_fragment != null) {
				instance_dispose_fragment.append (new CCodeExpressionStatement (get_unref_expression (lhs, f.type_reference)));
			}
		}
	}

	public override void visit_begin_method (Method! m) {
		current_symbol = m.symbol;
		current_return_type = m.return_type;
	}
	
	private ref CCodeStatement create_method_type_check_statement (Method! m, DataType! t, bool non_null, string! var_name) {
		return create_type_check_statement (m, m.return_type.data_type, t, non_null, var_name);
	}
	
	private ref CCodeStatement create_property_type_check_statement (Property! prop, bool getter, DataType! t, bool non_null, string! var_name) {
		if (getter) {
			return create_type_check_statement (prop, prop.type_reference.data_type, t, non_null, var_name);
		} else {
			return create_type_check_statement (prop, null, t, non_null, var_name);
		}
	}
	
	private ref CCodeStatement create_type_check_statement (CodeNode! method_node, DataType ret_type, DataType! t, bool non_null, string! var_name) {
		var ccheck = new CCodeFunctionCall ();
		
		if (t is Class || t is Interface) {
			var ctype_check = new CCodeFunctionCall (new CCodeIdentifier (t.get_upper_case_cname ("IS_")));
			ctype_check.add_argument (new CCodeIdentifier (var_name));
			
			ref CCodeExpression cexpr = ctype_check;
			if (!non_null) {
				var cnull = new CCodeBinaryExpression (CCodeBinaryOperator.EQUALITY, new CCodeIdentifier (var_name), new CCodeConstant ("NULL"));
			
				cexpr = new CCodeBinaryExpression (CCodeBinaryOperator.OR, cnull, ctype_check);
			}
			ccheck.add_argument (cexpr);
		} else if (!non_null) {
			return null;
		} else {
			var cnonnull = new CCodeBinaryExpression (CCodeBinaryOperator.INEQUALITY, new CCodeIdentifier (var_name), new CCodeConstant ("NULL"));
			ccheck.add_argument (cnonnull);
		}
		
		if (ret_type == null) {
			/* void function */
			ccheck.call = new CCodeIdentifier ("g_return_if_fail");
		} else {
			ccheck.call = new CCodeIdentifier ("g_return_val_if_fail");
			
			if (ret_type.is_reference_type ()) {
				ccheck.add_argument (new CCodeConstant ("NULL"));
			} else if (ret_type == bool_type.data_type) {
				ccheck.add_argument (new CCodeConstant ("FALSE"));
			} else if (ret_type == char_type.data_type ||
			           ret_type == unichar_type.data_type ||
			           ret_type == short_type.data_type ||
			           ret_type == ushort_type.data_type ||
			           ret_type == int_type.data_type ||
			           ret_type == uint_type.data_type ||
			           ret_type == long_type.data_type ||
			           ret_type == ulong_type.data_type ||
			           ret_type == int64_type.data_type ||
			           ret_type == uint64_type.data_type ||
			           ret_type == double_type.data_type ||
			           ret_type == float_type.data_type ||
			           ret_type is Enum || ret_type is Flags) {
				ccheck.add_argument (new CCodeConstant ("0"));
			} else {
				Report.warning (method_node.source_reference, "not supported return type for runtime type checks");
				return new CCodeExpressionStatement (new CCodeConstant ("0"));
			}
		}
		
		return new CCodeExpressionStatement (ccheck);
	}

	private DataType find_parent_type (CodeNode node) {
		var sym = node.symbol;
		while (sym != null) {
			if (sym.node is DataType) {
				return (DataType) sym.node;
			}
			sym = sym.parent_symbol;
		}
		return null;
	}
	
	private ref string! get_array_length_cname (string! array_cname, int dim) {
		return "%s_length%d".printf (array_cname, dim);
	}

	public override void visit_end_method (Method! m) {
		current_symbol = current_symbol.parent_symbol;
		current_return_type = null;

		if (current_symbol.parent_symbol != null &&
		    current_symbol.parent_symbol.node is Method) {
			/* lambda expressions produce nested methods */
			var up_method = (Method) current_symbol.parent_symbol.node;
			current_return_type = up_method.return_type;
		}

		function = new CCodeFunction (m.get_real_cname (), m.return_type.get_cname ());
		CCodeFunctionDeclarator vdeclarator = null;
		
		CCodeFormalParameter instance_param = null;
		
		if (m.instance) {
			var this_type = new TypeReference ();
			this_type.data_type = find_parent_type (m);
			if (m.base_interface_method != null) {
				var base_type = new TypeReference ();
				base_type.data_type = (DataType) m.base_interface_method.symbol.parent_symbol.node;
				instance_param = new CCodeFormalParameter ("base", base_type.get_cname ());
			} else if (m.overrides) {
				var base_type = new TypeReference ();
				base_type.data_type = (DataType) m.base_method.symbol.parent_symbol.node;
				instance_param = new CCodeFormalParameter ("base", base_type.get_cname ());
			} else {
				if (m.instance_by_reference) {
					instance_param = new CCodeFormalParameter ("*self", this_type.get_cname ());
				} else {
					instance_param = new CCodeFormalParameter ("self", this_type.get_cname ());
				}
			}
			if (!m.instance_last) {
				function.add_parameter (instance_param);
			}
			
			if (m.is_abstract || m.is_virtual) {
				var vdecl = new CCodeDeclaration (m.return_type.get_cname ());
				vdeclarator = new CCodeFunctionDeclarator (m.name);
				vdecl.add_declarator (vdeclarator);
				type_struct.add_declaration (vdecl);

				vdeclarator.add_parameter (instance_param);
			}
		}
		
		var params = m.get_parameters ();
		foreach (FormalParameter param in params) {
			if (!param.no_array_length && param.type_reference.data_type is Array) {
				var arr = (Array) param.type_reference.data_type;
				
				var length_ctype = "int";
				if (param.type_reference.is_out) {
					length_ctype = "int*";
				}
				
				for (int dim = 1; dim <= arr.rank; dim++) {
					var cparam = new CCodeFormalParameter (get_array_length_cname (param.name, dim), length_ctype);
					function.add_parameter (cparam);
					if (vdeclarator != null) {
						vdeclarator.add_parameter (cparam);
					}
				}
			}
		
			function.add_parameter ((CCodeFormalParameter) param.ccodenode);
			if (vdeclarator != null) {
				vdeclarator.add_parameter ((CCodeFormalParameter) param.ccodenode);
			}
		}
		
		if (m.instance && m.instance_last) {
			function.add_parameter (instance_param);
		}

		/* real function declaration and definition not needed
		 * for abstract methods */
		if (!m.is_abstract) {
			if (m.access != MemberAccessibility.PRIVATE && m.base_method == null && m.base_interface_method == null) {
				/* public methods need function declaration in
				 * header file except virtual/overridden methods */
				header_type_member_declaration.append (function.copy ());
			} else {
				/* declare all other functions in source file to
				 * avoid dependency on order within source file */
				function.modifiers |= CCodeModifiers.STATIC;
				source_type_member_declaration.append (function.copy ());
			}
			
			/* Methods imported from a plain C file don't
			 * have a body, e.g. Vala.Parser.parse_file () */
			if (m.body != null) {
				function.block = (CCodeBlock) m.body.ccodenode;

				var cinit = new CCodeFragment ();
				function.block.prepend_statement (cinit);

				if (m.symbol.parent_symbol.node is Class) {
					var cl = (Class) m.symbol.parent_symbol.node;
					if (m.overrides || m.base_interface_method != null) {
						var ccall = new CCodeFunctionCall (new CCodeIdentifier (cl.get_upper_case_cname (null)));
						ccall.add_argument (new CCodeIdentifier ("base"));
						
						var cdecl = new CCodeDeclaration ("%s *".printf (cl.get_cname ()));
						cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("self", ccall));
						
						cinit.append (cdecl);
					} else if (m.instance) {
						cinit.append (create_method_type_check_statement (m, cl, true, "self"));
					}
				}
				foreach (FormalParameter param in m.get_parameters ()) {
					var t = param.type_reference.data_type;
					if (t != null && t.is_reference_type () && !param.type_reference.is_out) {
						var type_check = create_method_type_check_statement (m, t, param.type_reference.non_null, param.name);
						if (type_check != null) {
							cinit.append (type_check);
						}
					}
				}

				if (m.source_reference != null && m.source_reference.comment != null) {
					source_type_member_definition.append (new CCodeComment (m.source_reference.comment));
				}
				source_type_member_definition.append (function);
				
				if (m is CreationMethod && current_class != null) {
					// declare construction parameter array
					var cparamsinit = new CCodeFunctionCall (new CCodeIdentifier ("g_new0"));
					cparamsinit.add_argument (new CCodeIdentifier ("GParameter"));
					cparamsinit.add_argument (new CCodeConstant (((CreationMethod)m).n_construction_params.to_string ()));
					
					var cdecl = new CCodeDeclaration ("GParameter *");
					cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("__params", cparamsinit));
					cinit.append (cdecl);
					
					cdecl = new CCodeDeclaration ("GParameter *");
					cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("__params_it", new CCodeIdentifier ("__params")));
					cinit.append (cdecl);
				}

				if (context.module_init_method == m && in_plugin) {
					// GTypeModule-based plug-in, register types
					cinit.append (module_init_fragment);
				}
			}
		}
		
		if (m.is_abstract || m.is_virtual) {
			var vfunc = new CCodeFunction (m.get_cname (), m.return_type.get_cname ());

			var this_type = new TypeReference ();
			this_type.data_type = (DataType) m.symbol.parent_symbol.node;

			var cparam = new CCodeFormalParameter ("self", this_type.get_cname ());
			vfunc.add_parameter (cparam);
			
			var vblock = new CCodeBlock ();
			
			CCodeFunctionCall vcast = null;
			if (m.symbol.parent_symbol.node is Interface) {
				var iface = (Interface) m.symbol.parent_symbol.node;

				vcast = new CCodeFunctionCall (new CCodeIdentifier ("%s_GET_INTERFACE".printf (iface.get_upper_case_cname (null))));
			} else {
				var cl = (Class) m.symbol.parent_symbol.node;

				vcast = new CCodeFunctionCall (new CCodeIdentifier ("%s_GET_CLASS".printf (cl.get_upper_case_cname (null))));
			}
			vcast.add_argument (new CCodeIdentifier ("self"));
		
			var vcall = new CCodeFunctionCall (new CCodeMemberAccess.pointer (vcast, m.name));
			vcall.add_argument (new CCodeIdentifier ("self"));
		
			var params = m.get_parameters ();
			foreach (FormalParameter param in params) {
				vfunc.add_parameter ((CCodeFormalParameter) param.ccodenode);
				vcall.add_argument (new CCodeIdentifier (param.name));
			}

			if (m.return_type.data_type == null) {
				vblock.add_statement (new CCodeExpressionStatement (vcall));
			} else {
				/* pass method return value */
				vblock.add_statement (new CCodeReturnStatement (vcall));
			}

			header_type_member_declaration.append (vfunc.copy ());
			
			vfunc.block = vblock;
			
			source_type_member_definition.append (vfunc);
		}
		
		if (m is CreationMethod) {
			var creturn = new CCodeReturnStatement ();
			creturn.return_expression = new CCodeIdentifier ("self");
			function.block.add_statement (creturn);
		}
		
		bool return_value = true;
		bool args_parameter = true;
		if (is_possible_entry_point (m, ref return_value, ref args_parameter)) {
			// m is possible entry point, add appropriate startup code
			var cmain = new CCodeFunction ("main", "int");
			cmain.add_parameter (new CCodeFormalParameter ("argc", "int"));
			cmain.add_parameter (new CCodeFormalParameter ("argv", "char **"));
			var main_block = new CCodeBlock ();
			main_block.add_statement (new CCodeExpressionStatement (new CCodeFunctionCall (new CCodeIdentifier ("g_type_init"))));
			var main_call = new CCodeFunctionCall (new CCodeIdentifier (function.name));
			if (args_parameter) {
				main_call.add_argument (new CCodeIdentifier ("argc"));
				main_call.add_argument (new CCodeIdentifier ("argv"));
			}
			if (return_value) {
				main_block.add_statement (new CCodeReturnStatement (main_call));
			} else {
				// method returns void, always use 0 as exit code
				main_block.add_statement (new CCodeExpressionStatement (main_call));
				main_block.add_statement (new CCodeReturnStatement (new CCodeConstant ("0")));
			}
			cmain.block = main_block;
			source_type_member_definition.append (cmain);
		}
	}
	
	public override void visit_begin_creation_method (CreationMethod! m) {
		current_symbol = m.symbol;
		current_return_type = m.return_type;
	}
	
	public override void visit_end_creation_method (CreationMethod! m) {
		visit_end_method (m);
	}
	
	private bool is_possible_entry_point (Method! m, ref bool return_value, ref bool args_parameter) {
		if (m.name == null || m.name != "main") {
			// method must be called "main"
			return false;
		}
		
		if (m.instance) {
			// method must be static
			return false;
		}
		
		if (m.return_type.data_type == null) {
			return_value = false;
		} else if (m.return_type.data_type == int_type.data_type) {
			return_value = true;
		} else {
			// return type must be void or int
			return false;
		}
		
		var params = m.get_parameters ();
		if (params.length () == 0) {
			// method may have no parameters
			args_parameter = false;
			return true;
		}
		
		if (params.length () > 1) {
			// method must not have more than one parameter
			return false;
		}
		
		var param = (FormalParameter) params.data;

		if (param.type_reference.is_out) {
			// parameter must not be an out parameter
			return false;
		}
		
		if (!(param.type_reference.data_type is Array)) {
			// parameter must be an array
			return false;
		}
		
		var array_type = (Array) param.type_reference.data_type;
		if (array_type.element_type != string_type.data_type) {
			// parameter must be an array of strings
			return false;
		}
		
		args_parameter = true;
		return true;
	}
	
	public override void visit_formal_parameter (FormalParameter! p) {
		if (!p.ellipsis) {
			p.ccodenode = new CCodeFormalParameter (p.name, p.type_reference.get_cname ());
		}
	}

	public override void visit_end_property (Property! prop) {
		if (!prop.is_abstract) {
			prop_enum.add_value (prop.get_upper_case_cname (), null);
		}
	}

	public override void visit_begin_property_accessor (PropertyAccessor! acc) {
		var prop = (Property) acc.symbol.parent_symbol.node;
		
		if (acc.readable) {
			current_return_type = prop.type_reference;
		} else {
			// void
			current_return_type = new TypeReference ();
		}
	}

	public override void visit_end_property_accessor (PropertyAccessor! acc) {
		var prop = (Property) acc.symbol.parent_symbol.node;

		current_return_type = null;

		var t = (DataType) prop.symbol.parent_symbol.node;

		var this_type = new TypeReference ();
		this_type.data_type = t;
		var cselfparam = new CCodeFormalParameter ("self", this_type.get_cname ());
		var cvalueparam = new CCodeFormalParameter ("value", prop.type_reference.get_cname (false, true));

		if (prop.is_abstract || prop.is_virtual) {
			if (acc.readable) {
				function = new CCodeFunction ("%s_get_%s".printf (t.get_lower_case_cname (null), prop.name), prop.type_reference.get_cname ());
			} else {
				function = new CCodeFunction ("%s_set_%s".printf (t.get_lower_case_cname (null), prop.name), "void");
			}
			function.add_parameter (cselfparam);
			if (acc.writable || acc.construction) {
				function.add_parameter (cvalueparam);
			}
			
			header_type_member_declaration.append (function.copy ());
			
			var block = new CCodeBlock ();
			function.block = block;

			if (acc.readable) {
				// declare temporary variable to save the property value
				var decl = new CCodeDeclaration (prop.type_reference.get_cname ());
				decl.add_declarator (new CCodeVariableDeclarator ("value"));
				block.add_statement (decl);
			
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_object_get"));
			
				var ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT"));
				ccast.add_argument (new CCodeIdentifier ("self"));
				ccall.add_argument (ccast);
				
				// property name is second argument of g_object_get
				ccall.add_argument (prop.get_canonical_cconstant ());

				ccall.add_argument (new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, new CCodeIdentifier ("value")));

				ccall.add_argument (new CCodeConstant ("NULL"));
				
				block.add_statement (new CCodeExpressionStatement (ccall));
				block.add_statement (new CCodeReturnStatement (new CCodeIdentifier ("value")));
			} else {
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_object_set"));
			
				var ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT"));
				ccast.add_argument (new CCodeIdentifier ("self"));
				ccall.add_argument (ccast);
				
				// property name is second argument of g_object_set
				ccall.add_argument (prop.get_canonical_cconstant ());

				ccall.add_argument (new CCodeIdentifier ("value"));

				ccall.add_argument (new CCodeConstant ("NULL"));
				
				block.add_statement (new CCodeExpressionStatement (ccall));
			}

			source_type_member_definition.append (function);
		}

		if (!prop.is_abstract) {
			bool is_virtual = prop.base_property != null || prop.base_interface_property != null;

			string prefix = t.get_lower_case_cname (null);
			if (is_virtual) {
				prefix += "_real";
			}
			if (acc.readable) {
				function = new CCodeFunction ("%s_get_%s".printf (prefix, prop.name), prop.type_reference.get_cname ());
			} else {
				function = new CCodeFunction ("%s_set_%s".printf (prefix, prop.name), "void");
			}
			if (is_virtual) {
				function.modifiers |= CCodeModifiers.STATIC;
			}
			function.add_parameter (cselfparam);
			if (acc.writable || acc.construction) {
				function.add_parameter (cvalueparam);
			}

			if (!is_virtual) {
				header_type_member_declaration.append (function.copy ());
			}
			
			if (acc.body != null) {
				function.block = (CCodeBlock) acc.body.ccodenode;

				function.block.prepend_statement (create_property_type_check_statement (prop, acc.readable, t, true, "self"));
			}
			
			source_type_member_definition.append (function);
		}
	}
	
	private string get_marshaller_type_name (TypeReference t) {
		if (t.type_parameter != null) {
			return ("POINTER");
		} else if (t.data_type == null) {
			return ("VOID");
		} else {
			return t.data_type.get_marshaller_type_name ();
		}
	}
	
	private ref string get_signal_marshaller_function (Signal! sig, string prefix = null) {
		var signature = get_signal_signature (sig);
		string ret;
		var params = sig.get_parameters ();
		
		if (prefix == null) {
			// FIXME remove equality check with cast in next revision
			if (predefined_marshal_list.lookup (signature) != (bool) null) {
				prefix = "g_cclosure_marshal";
			} else {
				prefix = "g_cclosure_user_marshal";
			}
		}
		
		ret = "%s_%s_".printf (prefix, get_marshaller_type_name (sig.return_type));
		
		if (params == null) {
			ret = ret + "_VOID";
		} else {
			foreach (FormalParameter p in params) {
				ret = "%s_%s".printf (ret, get_marshaller_type_name (p.type_reference));
			}
		}
		
		return ret;
	}
	
	private string get_value_type_name_from_type_reference (TypeReference! t) {
		if (t.type_parameter != null) {
			return "gpointer";
		} else if (t.data_type == null) {
			return "void";
		} else if (t.data_type is Class || t.data_type is Interface) {
			return "GObject *";
		} else if (t.data_type is Struct) {
			if (((Struct) t.data_type).is_reference_type ()) {
				return "gpointer";
			} else {
				return t.data_type.get_cname ();
			}
		} else if (t.data_type is Enum) {
			return "gint";
		} else if (t.data_type is Flags) {
			return "guint";
		} else if (t.data_type is Array) {
			return "gpointer";
		}
		
		return null;
	}
	
	private ref string get_signal_signature (Signal! sig) {
		string signature;
		var params = sig.get_parameters ();
		
		signature = "%s:".printf (get_marshaller_type_name (sig.return_type));
		if (params == null) {
			signature = signature + "VOID";
		} else {
			bool first = true;
			foreach (FormalParameter p in params) {
				if (first) {
					signature = signature + get_marshaller_type_name (p.type_reference);
					first = false;
				} else {
					signature = "%s,%s".printf (signature, get_marshaller_type_name (p.type_reference));
				}
			}
		}
		
		return signature;
	}
	
	public override void visit_end_signal (Signal! sig) {
		string signature;
		var params = sig.get_parameters ();
		int n_params, i;
		
		/* check whether a signal with the same signature already exists for this source file (or predefined) */
		signature = get_signal_signature (sig);
		// FIXME remove equality checks with cast in next revision
		if (predefined_marshal_list.lookup (signature) != (bool) null || user_marshal_list.lookup (signature) != (bool) null) {
			return;
		}
		
		var signal_marshaller = new CCodeFunction (get_signal_marshaller_function (sig), "void");
		signal_marshaller.modifiers = CCodeModifiers.STATIC;
		
		signal_marshaller.add_parameter (new CCodeFormalParameter ("closure", "GClosure *"));
		signal_marshaller.add_parameter (new CCodeFormalParameter ("return_value", "GValue *"));
		signal_marshaller.add_parameter (new CCodeFormalParameter ("n_param_values", "guint"));
		signal_marshaller.add_parameter (new CCodeFormalParameter ("param_values", "const GValue *"));
		signal_marshaller.add_parameter (new CCodeFormalParameter ("invocation_hint", "gpointer"));
		signal_marshaller.add_parameter (new CCodeFormalParameter ("marshal_data", "gpointer"));
		
		source_signal_marshaller_declaration.append (signal_marshaller.copy ());
		
		var marshaller_body = new CCodeBlock ();
		
		var callback_decl = new CCodeFunctionDeclarator (get_signal_marshaller_function (sig, "GMarshalFunc"));
		callback_decl.add_parameter (new CCodeFormalParameter ("data1", "gpointer"));
		n_params = 1;
		foreach (FormalParameter p in params) {
			callback_decl.add_parameter (new CCodeFormalParameter ("arg_%d".printf (n_params), get_value_type_name_from_type_reference (p.type_reference)));
			n_params++;
		}
		callback_decl.add_parameter (new CCodeFormalParameter ("data2", "gpointer"));
		marshaller_body.add_statement (new CCodeTypeDefinition (get_value_type_name_from_type_reference (sig.return_type), callback_decl));
		
		var var_decl = new CCodeDeclaration (get_signal_marshaller_function (sig, "GMarshalFunc"));
		var_decl.modifiers = CCodeModifiers.REGISTER;
		var_decl.add_declarator (new CCodeVariableDeclarator ("callback"));
		marshaller_body.add_statement (var_decl);
		
		var_decl = new CCodeDeclaration ("GCClosure *");
		var_decl.modifiers = CCodeModifiers.REGISTER;
		var_decl.add_declarator (new CCodeVariableDeclarator.with_initializer ("cc", new CCodeCastExpression (new CCodeIdentifier ("closure"), "GCClosure *")));
		marshaller_body.add_statement (var_decl);
		
		var_decl = new CCodeDeclaration ("gpointer");
		var_decl.modifiers = CCodeModifiers.REGISTER;
		var_decl.add_declarator (new CCodeVariableDeclarator ("data1"));
		var_decl.add_declarator (new CCodeVariableDeclarator ("data2"));
		marshaller_body.add_statement (var_decl);
		
		CCodeFunctionCall fc;
		
		if (sig.return_type.data_type != null) {
			var_decl = new CCodeDeclaration (get_value_type_name_from_type_reference (sig.return_type));
			var_decl.add_declarator (new CCodeVariableDeclarator ("v_return"));
			marshaller_body.add_statement (var_decl);
			
			fc = new CCodeFunctionCall (new CCodeIdentifier ("g_return_if_fail"));
			fc.add_argument (new CCodeBinaryExpression (CCodeBinaryOperator.INEQUALITY, new CCodeIdentifier ("return_value"), new CCodeConstant ("NULL")));
			marshaller_body.add_statement (new CCodeExpressionStatement (fc));
		}
		
		fc = new CCodeFunctionCall (new CCodeIdentifier ("g_return_if_fail"));
		fc.add_argument (new CCodeBinaryExpression (CCodeBinaryOperator.EQUALITY, new CCodeIdentifier ("n_param_values"), new CCodeConstant (n_params.to_string())));
		marshaller_body.add_statement (new CCodeExpressionStatement (fc));
		
		var data = new CCodeMemberAccess (new CCodeIdentifier ("closure"), "data", true);
		var param = new CCodeMemberAccess (new CCodeMemberAccess (new CCodeIdentifier ("param_values"), "data[0]", true), "v_pointer");
		var cond = new CCodeFunctionCall (new CCodeConstant ("G_CCLOSURE_SWAP_DATA"));
		cond.add_argument (new CCodeIdentifier ("closure"));
		var true_block = new CCodeBlock ();
		true_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("data1"), data)));
		true_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("data2"), param)));
		var false_block = new CCodeBlock ();
		false_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("data1"), param)));
		false_block.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("data2"), data)));
		marshaller_body.add_statement (new CCodeIfStatement (cond, true_block, false_block));
		
		var c_assign = new CCodeAssignment (new CCodeIdentifier ("callback"), new CCodeCastExpression (new CCodeConditionalExpression (new CCodeIdentifier ("marshal_data"), new CCodeIdentifier ("marshal_data"), new CCodeMemberAccess (new CCodeIdentifier ("cc"), "callback", true)), get_signal_marshaller_function (sig, "GMarshalFunc")));
		marshaller_body.add_statement (new CCodeExpressionStatement (c_assign));
		
		fc = new CCodeFunctionCall (new CCodeIdentifier ("callback"));
		fc.add_argument (new CCodeIdentifier ("data1"));
		i = 1;
		foreach (FormalParameter p in params) {
			string get_value_function;
			if (p.type_reference.type_parameter != null) {
				get_value_function = "g_value_get_pointer";
			} else {
				get_value_function = p.type_reference.data_type.get_get_value_function ();
			}
			var inner_fc = new CCodeFunctionCall (new CCodeIdentifier (get_value_function));
			inner_fc.add_argument (new CCodeBinaryExpression (CCodeBinaryOperator.PLUS, new CCodeIdentifier ("param_values"), new CCodeIdentifier (i.to_string ())));
			fc.add_argument (inner_fc);
			i++;
		}
		fc.add_argument (new CCodeIdentifier ("data2"));
		
		if (sig.return_type.data_type != null) {
			marshaller_body.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("v_return"), fc)));
			
			CCodeFunctionCall set_fc;
			if (sig.return_type.type_parameter != null) {
				set_fc = new CCodeFunctionCall (new CCodeIdentifier ("g_value_set_pointer"));
			} else if (sig.return_type.data_type is Class || sig.return_type.data_type is Interface) {
				set_fc = new CCodeFunctionCall (new CCodeIdentifier ("g_value_take_object"));
			} else if (sig.return_type.data_type == string_type.data_type) {
				set_fc = new CCodeFunctionCall (new CCodeIdentifier ("g_value_take_string"));
			} else {
				set_fc = new CCodeFunctionCall (new CCodeIdentifier (sig.return_type.data_type.get_set_value_function ()));
			}
			set_fc.add_argument (new CCodeIdentifier ("return_value"));
			set_fc.add_argument (new CCodeIdentifier ("v_return"));
			
			marshaller_body.add_statement (new CCodeExpressionStatement (set_fc));
		} else {
			marshaller_body.add_statement (new CCodeExpressionStatement (fc));
		}
		
		signal_marshaller.block = marshaller_body;
		
		source_signal_marshaller_definition.append (signal_marshaller);
		user_marshal_list.insert (signature, true);
	}
	
	public override void visit_end_constructor (Constructor! c) {
		var cl = (Class) c.symbol.parent_symbol.node;
	
		function = new CCodeFunction ("%s_constructor".printf (cl.get_lower_case_cname (null)), "GObject *");
		function.modifiers = CCodeModifiers.STATIC;
		
		function.add_parameter (new CCodeFormalParameter ("type", "GType"));
		function.add_parameter (new CCodeFormalParameter ("n_construct_properties", "guint"));
		function.add_parameter (new CCodeFormalParameter ("construct_properties", "GObjectConstructParam *"));
		
		source_type_member_declaration.append (function.copy ());


		var cblock = new CCodeBlock ();
		var cdecl = new CCodeDeclaration ("GObject *");
		cdecl.add_declarator (new CCodeVariableDeclarator ("obj"));
		cblock.add_statement (cdecl);

		cdecl = new CCodeDeclaration ("%sClass *".printf (cl.get_cname ()));
		cdecl.add_declarator (new CCodeVariableDeclarator ("klass"));
		cblock.add_statement (cdecl);

		cdecl = new CCodeDeclaration ("GObjectClass *");
		cdecl.add_declarator (new CCodeVariableDeclarator ("parent_class"));
		cblock.add_statement (cdecl);


		var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_class_peek"));
		ccall.add_argument (new CCodeIdentifier (cl.get_upper_case_cname ("TYPE_")));
		var ccast = new CCodeFunctionCall (new CCodeIdentifier ("%s_CLASS".printf (cl.get_upper_case_cname (null))));
		ccast.add_argument (ccall);
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("klass"), ccast)));

		ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_type_class_peek_parent"));
		ccall.add_argument (new CCodeIdentifier ("klass"));
		ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT_CLASS"));
		ccast.add_argument (ccall);
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("parent_class"), ccast)));

		
		ccall = new CCodeFunctionCall (new CCodeMemberAccess.pointer (new CCodeIdentifier ("parent_class"), "constructor"));
		ccall.add_argument (new CCodeIdentifier ("type"));
		ccall.add_argument (new CCodeIdentifier ("n_construct_properties"));
		ccall.add_argument (new CCodeIdentifier ("construct_properties"));
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("obj"), ccall)));


		ccall = new CCodeFunctionCall (new CCodeIdentifier (cl.get_upper_case_cname (null)));
		ccall.add_argument (new CCodeIdentifier ("obj"));
		
		cdecl = new CCodeDeclaration ("%s *".printf (cl.get_cname ()));
		cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer ("self", ccall));
		
		cblock.add_statement (cdecl);


		cblock.add_statement (c.body.ccodenode);
		
		cblock.add_statement (new CCodeReturnStatement (new CCodeIdentifier ("obj")));
		
		function.block = cblock;

		if (c.source_reference.comment != null) {
			source_type_member_definition.append (new CCodeComment (c.source_reference.comment));
		}
		source_type_member_definition.append (function);
	}

	public override void visit_begin_block (Block! b) {
		current_symbol = b.symbol;
	}
	
	private void add_object_creation (CCodeBlock! b) {
		var cl = (Class) current_type_symbol.node;
	
		var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_object_newv"));
		ccall.add_argument (new CCodeConstant (cl.get_type_id ()));
		ccall.add_argument (new CCodeConstant ("__params_it - __params"));
		ccall.add_argument (new CCodeConstant ("__params"));
		
		var cdecl = new CCodeVariableDeclarator ("self");
		cdecl.initializer = ccall;
		
		var cdeclaration = new CCodeDeclaration ("%s *".printf (cl.get_cname ()));
		cdeclaration.add_declarator (cdecl);
		
		b.add_statement (cdeclaration);
	}

	public override void visit_end_block (Block! b) {
		var local_vars = b.get_local_variables ();
		foreach (VariableDeclarator decl in local_vars) {
			decl.symbol.active = false;
		}
		
		bool in_construction = b.construction;
	
		var cblock = new CCodeBlock ();
		
		foreach (Statement stmt in b.get_statements ()) {
			if (in_construction && !stmt.construction) {
				// construction part of construction method ends here
				add_object_creation (cblock);
				in_construction = false;
			}
		
			var src = stmt.source_reference;
			if (src != null && src.comment != null) {
				cblock.add_statement (new CCodeComment (src.comment));
			}
			
			if (stmt.ccodenode is CCodeFragment) {
				foreach (CCodeStatement cstmt in ((CCodeFragment) stmt.ccodenode).get_children ()) {
					cblock.add_statement (cstmt);
				}
			} else {
				cblock.add_statement ((CCodeStatement) stmt.ccodenode);
			}
		}
		
		if (in_construction) {
			// construction method doesn't contain non-construction parts
			add_object_creation (cblock);
		}
		
		if (memory_management) {
			foreach (VariableDeclarator decl in local_vars) {
				if (decl.type_reference.data_type.is_reference_type () && decl.type_reference.takes_ownership) {
					cblock.add_statement (new CCodeExpressionStatement (get_unref_expression (new CCodeIdentifier (decl.name), decl.type_reference)));
				}
			}
		}
		
		b.ccodenode = cblock;

		current_symbol = current_symbol.parent_symbol;
	}

	public override void visit_empty_statement (EmptyStatement! stmt) {
		stmt.ccodenode = new CCodeEmptyStatement ();
	}

	public override void visit_declaration_statement (DeclarationStatement! stmt) {
		/* split declaration statement as var declarators
		 * might have different types */
	
		var cfrag = new CCodeFragment ();
		
		foreach (VariableDeclarator decl in stmt.declaration.get_variable_declarators ()) {
			var cdecl = new CCodeDeclaration (decl.type_reference.get_cname ());
		
			cdecl.add_declarator ((CCodeVariableDeclarator) decl.ccodenode);

			cfrag.append (cdecl);
			
			if (decl.initializer == null && decl.type_reference.data_type is Struct) {
				var st = (Struct) decl.type_reference.data_type;
				if (!st.is_reference_type () && st.get_fields ().length () > 0) {
					var czero = new CCodeFunctionCall (new CCodeIdentifier ("memset"));
					czero.add_argument (new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, new CCodeIdentifier (decl.name)));
					czero.add_argument (new CCodeConstant ("0"));
					czero.add_argument (new CCodeIdentifier ("sizeof (%s)".printf (decl.type_reference.get_cname ())));
					
					cfrag.append (new CCodeExpressionStatement (czero));
				}
			}
		}
		
		stmt.ccodenode = cfrag;

		foreach (VariableDeclarator decl in stmt.declaration.get_variable_declarators ()) {
			if (decl.initializer != null) {
				create_temp_decl (stmt, decl.initializer.temp_vars);
			}
		}

		create_temp_decl (stmt, temp_vars);
		temp_vars = null;
	}

	public override void visit_variable_declarator (VariableDeclarator! decl) {
		if (decl.type_reference.data_type is Array) {
			// create variables to store array dimensions
			var arr = (Array) decl.type_reference.data_type;
			
			for (int dim = 1; dim <= arr.rank; dim++) {
				var len_decl = new VariableDeclarator (get_array_length_cname (decl.name, dim));
				len_decl.type_reference = new TypeReference ();
				len_decl.type_reference.data_type = int_type.data_type;

				temp_vars.prepend (len_decl);
			}
		}
	
		CCodeExpression rhs = null;
		if (decl.initializer != null) {
			rhs = (CCodeExpression) decl.initializer.ccodenode;
			
			if (decl.type_reference.data_type != null
			    && decl.initializer.static_type.data_type != null
			    && decl.type_reference.data_type.is_reference_type ()
			    && decl.initializer.static_type.data_type != decl.type_reference.data_type) {
				// FIXME: use C cast if debugging disabled
				rhs = new InstanceCast (rhs, decl.type_reference.data_type);
			}

			if (decl.type_reference.data_type is Array) {
				var ccomma = new CCodeCommaExpression ();
				
				var temp_decl = get_temp_variable_declarator (decl.type_reference);
				temp_vars.prepend (temp_decl);
				ccomma.append_expression (new CCodeAssignment (new CCodeIdentifier (temp_decl.name), rhs));
				
				var lhs_array_len = new CCodeIdentifier (get_array_length_cname (decl.name, 1));
				var rhs_array_len = get_array_length_cexpression (decl.initializer, 1);
				ccomma.append_expression (new CCodeAssignment (lhs_array_len, rhs_array_len));
				
				ccomma.append_expression (new CCodeIdentifier (temp_decl.name));
				
				rhs = ccomma;
			}
		} else if (decl.type_reference.data_type != null && decl.type_reference.data_type.is_reference_type ()) {
			rhs = new CCodeConstant ("NULL");
		}
			
		decl.ccodenode = new CCodeVariableDeclarator.with_initializer (decl.name, rhs);

		decl.symbol.active = true;
	}

	public override void visit_end_initializer_list (InitializerList! list) {
		if (list.expected_type != null && list.expected_type.data_type is Array) {
			/* TODO */
		} else {
			var clist = new CCodeInitializerList ();
			foreach (Expression expr in list.get_initializers ()) {
				clist.append ((CCodeExpression) expr.ccodenode);
			}
			list.ccodenode = clist;
		}
	}
	
	private ref VariableDeclarator get_temp_variable_declarator (TypeReference! type, bool takes_ownership = true) {
		var decl = new VariableDeclarator ("__temp%d".printf (next_temp_var_id));
		decl.type_reference = type.copy ();
		decl.type_reference.reference_to_value_type = false;
		decl.type_reference.is_out = false;
		decl.type_reference.takes_ownership = takes_ownership;
		
		next_temp_var_id++;
		
		return decl;
	}
	
	private ref CCodeExpression get_unref_expression (CCodeExpression! cvar, TypeReference! type) {
		/* (foo == NULL ? NULL : foo = (unref (foo), NULL)) */
		
		/* can be simplified to
		 * foo = (unref (foo), NULL)
		 * if foo is of static type non-null
		 */

		var cisnull = new CCodeBinaryExpression (CCodeBinaryOperator.EQUALITY, cvar, new CCodeConstant ("NULL"));

		string unref_function;
		if (type.data_type.is_reference_counting ()) {
			unref_function = type.data_type.get_unref_function ();
		} else {
			unref_function = type.data_type.get_free_function ();
		}

		var ccall = new CCodeFunctionCall (new CCodeIdentifier (unref_function));
		ccall.add_argument (cvar);
		
		/* set freed references to NULL to prevent further use */
		var ccomma = new CCodeCommaExpression ();
		
		if (unref_function == "g_list_free") {
			bool is_ref = false;
			bool is_class = false;
			bool is_interface = false;

			foreach (TypeReference type_arg in type.get_type_arguments ()) {
				is_ref |= type_arg.takes_ownership;
				is_class |= type_arg.data_type is Class;
				is_interface |= type_arg.data_type is Interface;
			}
			
			if (is_ref) {
				var cunrefcall = new CCodeFunctionCall (new CCodeIdentifier ("g_list_foreach"));
				cunrefcall.add_argument (cvar);
				if (is_class || is_interface) {
					cunrefcall.add_argument (new CCodeIdentifier ("(GFunc) g_object_unref"));
				} else {
					cunrefcall.add_argument (new CCodeIdentifier ("(GFunc) g_free"));
				}
				cunrefcall.add_argument (new CCodeConstant ("NULL"));
				ccomma.append_expression (cunrefcall);
			}
		} else if (unref_function == "g_string_free") {
			ccall.add_argument (new CCodeConstant ("TRUE"));
		}
		
		ccomma.append_expression (ccall);
		ccomma.append_expression (new CCodeConstant ("NULL"));
		
		var cassign = new CCodeAssignment (cvar, ccomma);
		
		return new CCodeConditionalExpression (cisnull, new CCodeConstant ("NULL"), new CCodeParenthesizedExpression (cassign));
	}
	
	public override void visit_end_full_expression (Expression! expr) {
		if (!memory_management) {
			temp_vars = null;
			temp_ref_vars = null;
			return;
		}
	
		/* expr is a full expression, i.e. an initializer, the
		 * expression in an expression statement, the controlling
		 * expression in if, while, for, or foreach statements
		 *
		 * we unref temporary variables at the end of a full
		 * expression
		 */
		
		/* can't automatically deep copy lists yet, so do it
		 * manually for now
		 * replace with
		 * expr.temp_vars = temp_vars;
		 * when deep list copying works
		 */
		expr.temp_vars = null;
		foreach (VariableDeclarator decl1 in temp_vars) {
			expr.temp_vars.append (decl1);
		}
		temp_vars = null;

		if (temp_ref_vars == null) {
			/* nothing to do without temporary variables */
			return;
		}
		
		var full_expr_decl = get_temp_variable_declarator (expr.static_type);
		expr.temp_vars.append (full_expr_decl);
		
		var expr_list = new CCodeCommaExpression ();
		expr_list.append_expression (new CCodeAssignment (new CCodeIdentifier (full_expr_decl.name), (CCodeExpression) expr.ccodenode));
		
		foreach (VariableDeclarator decl in temp_ref_vars) {
			expr_list.append_expression (get_unref_expression (new CCodeIdentifier (decl.name), decl.type_reference));
		}
		
		expr_list.append_expression (new CCodeIdentifier (full_expr_decl.name));
		
		expr.ccodenode = expr_list;
		
		temp_ref_vars = null;
	}
	
	private void append_temp_decl (CCodeFragment! cfrag, List<VariableDeclarator> temp_vars) {
		foreach (VariableDeclarator decl in temp_vars) {
			var cdecl = new CCodeDeclaration (decl.type_reference.get_cname (true, !decl.type_reference.takes_ownership));
		
			var vardecl = new CCodeVariableDeclarator (decl.name);
			cdecl.add_declarator (vardecl);
			
			if (decl.type_reference.data_type != null && decl.type_reference.data_type.is_reference_type ()) {
				vardecl.initializer = new CCodeConstant ("NULL");
			}
			
			cfrag.append (cdecl);
		}
	}

	public override void visit_expression_statement (ExpressionStatement! stmt) {
		stmt.ccodenode = new CCodeExpressionStatement ((CCodeExpression) stmt.expression.ccodenode);
		
		/* free temporary objects */
		if (!memory_management) {
			temp_vars = null;
			temp_ref_vars = null;
			return;
		}
		
		if (temp_vars == null) {
			/* nothing to do without temporary variables */
			return;
		}
		
		var cfrag = new CCodeFragment ();
		append_temp_decl (cfrag, temp_vars);
		
		cfrag.append (stmt.ccodenode);
		
		foreach (VariableDeclarator decl in temp_ref_vars) {
			cfrag.append (new CCodeExpressionStatement (get_unref_expression (new CCodeIdentifier (decl.name), decl.type_reference)));
		}
		
		stmt.ccodenode = cfrag;
		
		temp_vars = null;
		temp_ref_vars = null;
	}
	
	private void create_temp_decl (Statement! stmt, List<VariableDeclarator> temp_vars) {
		/* declare temporary variables */
		
		if (temp_vars == null) {
			/* nothing to do without temporary variables */
			return;
		}
		
		var cfrag = new CCodeFragment ();
		append_temp_decl (cfrag, temp_vars);
		
		cfrag.append (stmt.ccodenode);
		
		stmt.ccodenode = cfrag;
	}

	public override void visit_if_statement (IfStatement! stmt) {
		if (stmt.false_statement != null) {
			stmt.ccodenode = new CCodeIfStatement ((CCodeExpression) stmt.condition.ccodenode, (CCodeStatement) stmt.true_statement.ccodenode, (CCodeStatement) stmt.false_statement.ccodenode);
		} else {
			stmt.ccodenode = new CCodeIfStatement ((CCodeExpression) stmt.condition.ccodenode, (CCodeStatement) stmt.true_statement.ccodenode);
		}
		
		create_temp_decl (stmt, stmt.condition.temp_vars);
	}

	public override void visit_switch_statement (SwitchStatement! stmt) {
		// we need a temporary variable to save the property value
		var temp_decl = get_temp_variable_declarator (stmt.expression.static_type);
		stmt.expression.temp_vars.prepend (temp_decl);

		var ctemp = new CCodeIdentifier (temp_decl.name);
		
		var cinit = new CCodeAssignment (ctemp, (CCodeExpression) stmt.expression.ccodenode);
		
		var cswitchblock = new CCodeFragment ();
		cswitchblock.append (new CCodeExpressionStatement (cinit));
		stmt.ccodenode = cswitchblock;

		create_temp_decl (stmt, stmt.expression.temp_vars);

		List<weak Statement> default_statements = null;
		
		// generate nested if statements		
		ref CCodeStatement ctopstmt = null;
		CCodeIfStatement coldif = null;
		foreach (SwitchSection section in stmt.get_sections ()) {
			if (section.has_default_label ()) {
				default_statements = section.get_statements ();
			} else {
				CCodeBinaryExpression cor = null;
				foreach (SwitchLabel label in section.get_labels ()) {
					var ccmp = new CCodeBinaryExpression (CCodeBinaryOperator.EQUALITY, ctemp, (CCodeExpression) label.expression.ccodenode);
					if (cor == null) {
						cor = ccmp;
					} else {
						cor = new CCodeBinaryExpression (CCodeBinaryOperator.OR, cor, ccmp);
					}
				}
				
				var cblock = new CCodeBlock ();
				foreach (Statement body_stmt in section.get_statements ()) {
					if (body_stmt.ccodenode is CCodeFragment) {
						foreach (CCodeStatement cstmt in ((CCodeFragment) body_stmt.ccodenode).get_children ()) {
							cblock.add_statement (cstmt);
						}
					} else {
						cblock.add_statement ((CCodeStatement) body_stmt.ccodenode);
					}
				}
				
				var cdo = new CCodeDoStatement (cblock, new CCodeConstant ("0"));
				
				var cif = new CCodeIfStatement (cor, cdo);
				if (coldif != null) {
					coldif.false_statement = cif;
				} else {
					ctopstmt = cif;
				}
				coldif = cif;
			}
		}
		
		if (default_statements != null) {
			var cblock = new CCodeBlock ();
			foreach (Statement body_stmt in default_statements) {
				cblock.add_statement ((CCodeStatement) body_stmt.ccodenode);
			}
			
			var cdo = new CCodeDoStatement (cblock, new CCodeConstant ("0"));

			if (coldif == null) {
				// there is only one section and that section
				// contains a default label
				ctopstmt = cdo;
			} else {
				coldif.false_statement = cdo;
			}
		}
		
		cswitchblock.append (ctopstmt);
	}

	public override void visit_while_statement (WhileStatement! stmt) {
		stmt.ccodenode = new CCodeWhileStatement ((CCodeExpression) stmt.condition.ccodenode, (CCodeStatement) stmt.body.ccodenode);
		
		create_temp_decl (stmt, stmt.condition.temp_vars);
	}

	public override void visit_do_statement (DoStatement! stmt) {
		stmt.ccodenode = new CCodeDoStatement ((CCodeStatement) stmt.body.ccodenode, (CCodeExpression) stmt.condition.ccodenode);
		
		create_temp_decl (stmt, stmt.condition.temp_vars);
	}

	public override void visit_for_statement (ForStatement! stmt) {
		var cfor = new CCodeForStatement ((CCodeExpression) stmt.condition.ccodenode, (CCodeStatement) stmt.body.ccodenode);
		
		foreach (Expression init_expr in stmt.get_initializer ()) {
			cfor.add_initializer ((CCodeExpression) init_expr.ccodenode);
		}
		
		foreach (Expression it_expr in stmt.get_iterator ()) {
			cfor.add_iterator ((CCodeExpression) it_expr.ccodenode);
		}
		
		stmt.ccodenode = cfor;
		
		create_temp_decl (stmt, stmt.condition.temp_vars);
	}

	public override void visit_end_foreach_statement (ForeachStatement! stmt) {
		var cblock = new CCodeBlock ();
		CCodeForStatement cfor;
		VariableDeclarator collection_backup = get_temp_variable_declarator (stmt.collection.static_type);
		
		stmt.collection.temp_vars.prepend (collection_backup);
		var cfrag = new CCodeFragment ();
		append_temp_decl (cfrag, stmt.collection.temp_vars);
		cblock.add_statement (cfrag);
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier (collection_backup.name), (CCodeExpression) stmt.collection.ccodenode)));
		
		stmt.ccodenode = cblock;
		
		if (stmt.collection.static_type.data_type is Array) {
			var arr = (Array) stmt.collection.static_type.data_type;
			
			var array_len = get_array_length_cexpression (stmt.collection, 1);
			
			/* the array has no length parameter i.e. is NULL-terminated array */
			if (array_len is CCodeConstant) {
				var it_name = "%s_it".printf (stmt.variable_name);
			
				var citdecl = new CCodeDeclaration (stmt.collection.static_type.get_cname ());
				citdecl.add_declarator (new CCodeVariableDeclarator (it_name));
				cblock.add_statement (citdecl);
				
				var cbody = new CCodeBlock ();
				
				var cdecl = new CCodeDeclaration (stmt.type_reference.get_cname ());
				cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer (stmt.variable_name, new CCodeIdentifier ("*%s".printf (it_name))));
				cbody.add_statement (cdecl);
				
				cbody.add_statement (stmt.body.ccodenode);
				
				var ccond = new CCodeBinaryExpression (CCodeBinaryOperator.INEQUALITY, new CCodeIdentifier ("*%s".printf (it_name)), new CCodeConstant ("NULL"));
				
				var cfor = new CCodeForStatement (ccond, cbody);

				cfor.add_initializer (new CCodeAssignment (new CCodeIdentifier (it_name), new CCodeIdentifier (collection_backup.name)));
		
				cfor.add_iterator (new CCodeAssignment (new CCodeIdentifier (it_name), new CCodeBinaryExpression (CCodeBinaryOperator.PLUS, new CCodeIdentifier (it_name), new CCodeConstant ("1"))));
				cblock.add_statement (cfor);
			/* the array has a length parameter */
			} else {
				var it_name = (stmt.variable_name + "_it");
			
				var citdecl = new CCodeDeclaration ("int");
				citdecl.add_declarator (new CCodeVariableDeclarator (it_name));
				cblock.add_statement (citdecl);
				
				var cbody = new CCodeBlock ();
				
				var cdecl = new CCodeDeclaration (stmt.type_reference.get_cname ());
				cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer (stmt.variable_name, new CCodeElementAccess (new CCodeIdentifier (collection_backup.name), new CCodeIdentifier (it_name))));
				cbody.add_statement (cdecl);

				cbody.add_statement (stmt.body.ccodenode);
				
				var ccond_ind1 = new CCodeBinaryExpression (CCodeBinaryOperator.INEQUALITY, array_len, new CCodeConstant ("-1"));
				var ccond_ind2 = new CCodeBinaryExpression (CCodeBinaryOperator.LESS_THAN, new CCodeIdentifier (it_name), array_len);
				var ccond_ind = new CCodeBinaryExpression (CCodeBinaryOperator.AND, ccond_ind1, ccond_ind2);
				
				/* only check for null if the containers elements are of reference-type */
				CCodeBinaryExpression ccond;
				if (arr.element_type.is_reference_type ()) {
					var ccond_term1 = new CCodeBinaryExpression (CCodeBinaryOperator.EQUALITY, array_len, new CCodeConstant ("-1"));
					var ccond_term2 = new CCodeBinaryExpression (CCodeBinaryOperator.INEQUALITY, new CCodeElementAccess (new CCodeIdentifier (collection_backup.name), new CCodeIdentifier (it_name)), new CCodeConstant ("NULL"));
					var ccond_term = new CCodeBinaryExpression (CCodeBinaryOperator.AND, ccond_term1, ccond_term2);

					ccond = new CCodeBinaryExpression (CCodeBinaryOperator.OR, new CCodeParenthesizedExpression (ccond_ind), new CCodeParenthesizedExpression (ccond_term));
				} else {
					ccond = ccond_ind;
				}
				
				var cfor = new CCodeForStatement (ccond, cbody);
				cfor.add_initializer (new CCodeAssignment (new CCodeIdentifier (it_name), new CCodeConstant ("0")));
				cfor.add_iterator (new CCodeAssignment (new CCodeIdentifier (it_name), new CCodeBinaryExpression (CCodeBinaryOperator.PLUS, new CCodeIdentifier (it_name), new CCodeConstant ("1"))));
				cblock.add_statement (cfor);
			}
		} else if (stmt.collection.static_type.data_type == list_type ||
		           stmt.collection.static_type.data_type == slist_type) {
			var it_name = "%s_it".printf (stmt.variable_name);
		
			var citdecl = new CCodeDeclaration (stmt.collection.static_type.get_cname ());
			citdecl.add_declarator (new CCodeVariableDeclarator (it_name));
			cblock.add_statement (citdecl);
			
			var cbody = new CCodeBlock ();
			
			var cdecl = new CCodeDeclaration (stmt.type_reference.get_cname ());
			cdecl.add_declarator (new CCodeVariableDeclarator.with_initializer (stmt.variable_name, new CCodeMemberAccess.pointer (new CCodeIdentifier (it_name), "data")));
			cbody.add_statement (cdecl);
			
			cbody.add_statement (stmt.body.ccodenode);
			
			var ccond = new CCodeBinaryExpression (CCodeBinaryOperator.INEQUALITY, new CCodeIdentifier (it_name), new CCodeConstant ("NULL"));
			
			var cfor = new CCodeForStatement (ccond, cbody);
			
			cfor.add_initializer (new CCodeAssignment (new CCodeIdentifier (it_name), new CCodeIdentifier (collection_backup.name)));

			cfor.add_iterator (new CCodeAssignment (new CCodeIdentifier (it_name), new CCodeMemberAccess.pointer (new CCodeIdentifier (it_name), "next")));
			cblock.add_statement (cfor);
		}
		
		if (memory_management && stmt.collection.static_type.transfers_ownership) {
			cblock.add_statement (new CCodeExpressionStatement (get_unref_expression (new CCodeIdentifier (collection_backup.name), stmt.collection.static_type)));
		}
	}

	public override void visit_break_statement (BreakStatement! stmt) {
		stmt.ccodenode = new CCodeBreakStatement ();
	}

	public override void visit_continue_statement (ContinueStatement! stmt) {
		stmt.ccodenode = new CCodeContinueStatement ();
	}
	
	private void append_local_free (Symbol sym, CCodeFragment cfrag, bool stop_at_loop) {
		var b = (Block) sym.node;

		var local_vars = b.get_local_variables ();
		foreach (VariableDeclarator decl in local_vars) {
			if (decl.symbol.active && decl.type_reference.data_type.is_reference_type () && decl.type_reference.takes_ownership) {
				cfrag.append (new CCodeExpressionStatement (get_unref_expression (new CCodeIdentifier (decl.name), decl.type_reference)));
			}
		}
		
		if (sym.parent_symbol.node is Block) {
			append_local_free (sym.parent_symbol, cfrag, stop_at_loop);
		}
	}

	private void create_local_free (Statement stmt) {
		if (!memory_management) {
			return;
		}
		
		var cfrag = new CCodeFragment ();
	
		append_local_free (current_symbol, cfrag, false);

		cfrag.append (stmt.ccodenode);
		stmt.ccodenode = cfrag;
	}
	
	private bool append_local_free_expr (Symbol sym, CCodeCommaExpression ccomma, bool stop_at_loop) {
		var found = false;
	
		var b = (Block) sym.node;

		var local_vars = b.get_local_variables ();
		foreach (VariableDeclarator decl in local_vars) {
			if (decl.symbol.active && decl.type_reference.data_type.is_reference_type () && decl.type_reference.takes_ownership) {
				found = true;
				ccomma.append_expression (get_unref_expression (new CCodeIdentifier (decl.name), decl.type_reference));
			}
		}
		
		if (sym.parent_symbol.node is Block) {
			found = found || append_local_free_expr (sym.parent_symbol, ccomma, stop_at_loop);
		}
		
		return found;
	}

	private void create_local_free_expr (Expression expr) {
		if (!memory_management) {
			return;
		}
		
		var return_expr_decl = get_temp_variable_declarator (expr.static_type);
		
		var ccomma = new CCodeCommaExpression ();
		ccomma.append_expression (new CCodeAssignment (new CCodeIdentifier (return_expr_decl.name), (CCodeExpression) expr.ccodenode));

		if (!append_local_free_expr (current_symbol, ccomma, false)) {
			/* no local variables need to be freed */
			return;
		}

		ccomma.append_expression (new CCodeIdentifier (return_expr_decl.name));
		
		expr.ccodenode = ccomma;
		expr.temp_vars.append (return_expr_decl);
	}

	public override void visit_begin_return_statement (ReturnStatement! stmt) {
		if (stmt.return_expression != null) {
			// avoid unnecessary ref/unref pair
			if (stmt.return_expression.ref_missing &&
			    stmt.return_expression.symbol_reference != null &&
			    stmt.return_expression.symbol_reference.node is VariableDeclarator) {
				var decl = (VariableDeclarator) stmt.return_expression.symbol_reference.node;
				if (decl.type_reference.takes_ownership) {
					/* return expression is local variable taking ownership and
					 * current method is transferring ownership */
					
					stmt.return_expression.ref_sink = true;

					// don't ref expression
					stmt.return_expression.ref_missing = false;
				}
			}
		}
	}

	public override void visit_end_return_statement (ReturnStatement! stmt) {
		if (stmt.return_expression == null) {
			stmt.ccodenode = new CCodeReturnStatement ();
			
			create_local_free (stmt);
		} else {
			Symbol return_expression_symbol = null;
		
			// avoid unnecessary ref/unref pair
			if (stmt.return_expression.ref_sink &&
			    stmt.return_expression.symbol_reference != null &&
			    stmt.return_expression.symbol_reference.node is VariableDeclarator) {
				var decl = (VariableDeclarator) stmt.return_expression.symbol_reference.node;
				if (decl.type_reference.takes_ownership) {
					/* return expression is local variable taking ownership and
					 * current method is transferring ownership */
					
					// don't unref expression
					return_expression_symbol = decl.symbol;
					return_expression_symbol.active = false;
				}
			}
		
			create_local_free_expr (stmt.return_expression);
			
			if (stmt.return_expression.static_type != null &&
			    stmt.return_expression.static_type.data_type != current_return_type.data_type) {
				/* cast required */
				if (current_return_type.data_type is Class || current_return_type.data_type is Interface) {
					stmt.return_expression.ccodenode = new InstanceCast ((CCodeExpression) stmt.return_expression.ccodenode, current_return_type.data_type);
				}
			}

			stmt.ccodenode = new CCodeReturnStatement ((CCodeExpression) stmt.return_expression.ccodenode);
		
			create_temp_decl (stmt, stmt.return_expression.temp_vars);

			if (return_expression_symbol != null) {
				return_expression_symbol.active = true;
			}
		}
	}
	
	private ref string get_symbol_lock_name (Symbol! sym) {
		return "__lock_%s".printf (sym.name);
	}
	
	/**
	 * Visit operation called for lock statements.
	 *
	 * @param stmt a lock statement
	 */
	public override void visit_lock_statement (LockStatement! stmt) {
		var cn = new CCodeFragment ();
		CCodeExpression l = null;
		CCodeFunctionCall fc;
		var inner_node = ((MemberAccess)stmt.resource).inner;
		
		if (inner_node  == null) {
			l = new CCodeIdentifier ("self");
		} else if (stmt.resource.symbol_reference.parent_symbol.node != current_class) {
			 l = new CCodeFunctionCall (new CCodeIdentifier (((DataType) stmt.resource.symbol_reference.parent_symbol.node).get_upper_case_cname ()));
			((CCodeFunctionCall) l).add_argument ((CCodeExpression)inner_node.ccodenode);
		} else {
			l = (CCodeExpression)inner_node.ccodenode;
		}
		l = new CCodeMemberAccess.pointer (new CCodeMemberAccess.pointer (l, "priv"), get_symbol_lock_name (stmt.resource.symbol_reference));
		
		fc = new CCodeFunctionCall (new CCodeIdentifier (((Method)mutex_type.data_type.symbol.lookup ("lock").node).get_cname ()));
		fc.add_argument (l);
		cn.append (new CCodeExpressionStatement (fc));
		
		cn.append (stmt.body.ccodenode);
		
		fc = new CCodeFunctionCall (new CCodeIdentifier (((Method)mutex_type.data_type.symbol.lookup ("unlock").node).get_cname ()));
		fc.add_argument (l);
		cn.append (new CCodeExpressionStatement (fc));
		
		stmt.ccodenode = cn;
	}
	
	/**
	 * Visit operations called for array creation expresions.
	 *
	 * @param expr an array creation expression
	 */
	public override void visit_end_array_creation_expression (ArrayCreationExpression! expr) {
		/* FIXME: rank > 1 not supported yet */
		if (expr.rank > 1) {
			expr.error = true;
			Report.error (expr.source_reference, "Creating arrays with rank greater than 1 is not supported yet");
		}
		
		var sizes = expr.get_sizes ();
		var gnew = new CCodeFunctionCall (new CCodeIdentifier ("g_new0"));
		gnew.add_argument (new CCodeIdentifier (expr.element_type.get_cname ()));
		/* FIXME: had to add Expression cast due to possible compiler bug */
		gnew.add_argument ((CCodeExpression) ((Expression) sizes.first ().data).ccodenode);
		
		if (expr.initializer_list != null) {
			var ce = new CCodeCommaExpression ();
			var temp_var = get_temp_variable_declarator (expr.static_type);
			var name_cnode = new CCodeIdentifier (temp_var.name);
			int i = 0;
			
			temp_vars.prepend (temp_var);
			
			/* FIXME: had to add Expression cast due to possible compiler bug */
			ce.append_expression (new CCodeAssignment (name_cnode, gnew));
			
			foreach (Expression e in expr.initializer_list.get_initializers ()) {
				ce.append_expression (new CCodeAssignment (new CCodeElementAccess (name_cnode, new CCodeConstant (i.to_string ())), (CCodeExpression) e.ccodenode));
				i++;
			}
			
			ce.append_expression (name_cnode);
			
			expr.ccodenode = ce;
		} else {
			expr.ccodenode = gnew;
		}
	}

	public override void visit_boolean_literal (BooleanLiteral! expr) {
		expr.ccodenode = new CCodeConstant (expr.value ? "TRUE" : "FALSE");
	}

	public override void visit_character_literal (CharacterLiteral! expr) {
		if (expr.get_char () >= 0x20 && expr.get_char () < 0x80) {
			expr.ccodenode = new CCodeConstant (expr.value);
		} else {
			expr.ccodenode = new CCodeConstant ("%uU".printf (expr.get_char ()));
		}
	}

	public override void visit_integer_literal (IntegerLiteral! expr) {
		expr.ccodenode = new CCodeConstant (expr.value);
	}

	public override void visit_real_literal (RealLiteral! expr) {
		expr.ccodenode = new CCodeConstant (expr.value);
	}

	public override void visit_string_literal (StringLiteral! expr) {
		expr.ccodenode = new CCodeConstant (expr.value);
	}

	public override void visit_null_literal (NullLiteral! expr) {
		expr.ccodenode = new CCodeConstant ("NULL");
	}

	public override void visit_literal_expression (LiteralExpression! expr) {
		expr.ccodenode = expr.literal.ccodenode;
		
		visit_expression (expr);
	}
	
	private void process_cmember (MemberAccess! expr, CCodeExpression pub_inst, DataType base_type) {
		if (expr.symbol_reference.node is Method) {
			var m = (Method) expr.symbol_reference.node;
			
			if (expr.inner is BaseAccess) {
				if (m.base_interface_method != null) {
					var base_iface = (Interface) m.base_interface_method.symbol.parent_symbol.node;
					string parent_iface_var = "%s_%s_parent_iface".printf (current_class.get_lower_case_cname (null), base_iface.get_lower_case_cname (null));

					expr.ccodenode = new CCodeMemberAccess.pointer (new CCodeIdentifier (parent_iface_var), m.name);
					return;
				} else if (m.base_method != null) {
					var base_class = (Class) m.base_method.symbol.parent_symbol.node;
					var vcast = new CCodeFunctionCall (new CCodeIdentifier ("%s_CLASS".printf (base_class.get_upper_case_cname (null))));
					vcast.add_argument (new CCodeIdentifier ("%s_parent_class".printf (current_class.get_lower_case_cname (null))));
					
					expr.ccodenode = new CCodeMemberAccess.pointer (vcast, m.name);
					return;
				}
			}
			
			if (m.base_interface_method != null) {
				expr.ccodenode = new CCodeIdentifier (m.base_interface_method.get_cname ());
			} else if (m.base_method != null) {
				expr.ccodenode = new CCodeIdentifier (m.base_method.get_cname ());
			} else {
				expr.ccodenode = new CCodeIdentifier (m.get_cname ());
			}
		} else if (expr.symbol_reference.node is ArrayLengthField) {
			expr.ccodenode = get_array_length_cexpression (expr.inner, 1);
		} else if (expr.symbol_reference.node is Field) {
			var f = (Field) expr.symbol_reference.node;
			if (f.instance) {
				ref CCodeExpression typed_inst;
				if (f.symbol.parent_symbol.node != base_type) {
					// FIXME: use C cast if debugging disabled
					typed_inst = new CCodeFunctionCall (new CCodeIdentifier (((DataType) f.symbol.parent_symbol.node).get_upper_case_cname (null)));
					((CCodeFunctionCall) typed_inst).add_argument (pub_inst);
				} else {
					typed_inst = pub_inst;
				}
				ref CCodeExpression inst;
				if (f.access == MemberAccessibility.PRIVATE) {
					inst = new CCodeMemberAccess.pointer (typed_inst, "priv");
				} else {
					inst = typed_inst;
				}
				if (((DataType) f.symbol.parent_symbol.node).is_reference_type ()) {
					expr.ccodenode = new CCodeMemberAccess.pointer (inst, f.get_cname ());
				} else {
					expr.ccodenode = new CCodeMemberAccess (inst, f.get_cname ());
				}
			} else {
				expr.ccodenode = new CCodeIdentifier (f.get_cname ());
			}
		} else if (expr.symbol_reference.node is Constant) {
			var c = (Constant) expr.symbol_reference.node;
			expr.ccodenode = new CCodeIdentifier (c.get_cname ());
		} else if (expr.symbol_reference.node is Property) {
			var prop = (Property) expr.symbol_reference.node;
			var cl = (Class) prop.symbol.parent_symbol.node;

			if (!prop.no_accessor_method) {
				var base_property = prop;
				if (prop.base_property != null) {
					base_property = prop.base_property;
				} else if (prop.base_interface_property != null) {
					base_property = prop.base_interface_property;
				}
				var base_property_type = (DataType) base_property.symbol.parent_symbol.node;
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("%s_get_%s".printf (base_property_type.get_lower_case_cname (null), base_property.name)));
				
				/* explicitly use strong reference as ccast
				 * gets unrefed at the end of the inner block
				 */
				ref CCodeExpression typed_pub_inst = pub_inst;

				/* cast if necessary */
				if (base_property_type != base_type) {
					// FIXME: use C cast if debugging disabled
					var ccast = new CCodeFunctionCall (new CCodeIdentifier (base_property_type.get_upper_case_cname (null)));
					ccast.add_argument (pub_inst);
					typed_pub_inst = ccast;
				}

				ccall.add_argument (typed_pub_inst);
				expr.ccodenode = ccall;
			} else {
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_object_get"));
			
				var ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT"));
				ccast.add_argument (pub_inst);
				ccall.add_argument (ccast);
				
				// property name is second argument of g_object_get
				ccall.add_argument (prop.get_canonical_cconstant ());
				
				
				// we need a temporary variable to save the property value
				var temp_decl = get_temp_variable_declarator (expr.static_type);
				temp_vars.prepend (temp_decl);

				var ctemp = new CCodeIdentifier (temp_decl.name);
				ccall.add_argument (new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, ctemp));
				
				
				ccall.add_argument (new CCodeConstant ("NULL"));
				
				var ccomma = new CCodeCommaExpression ();
				ccomma.append_expression (ccall);
				ccomma.append_expression (ctemp);
				expr.ccodenode = ccomma;
			}
		} else if (expr.symbol_reference.node is EnumValue) {
			var ev = (EnumValue) expr.symbol_reference.node;
			expr.ccodenode = new CCodeConstant (ev.get_cname ());
		} else if (expr.symbol_reference.node is VariableDeclarator) {
			var decl = (VariableDeclarator) expr.symbol_reference.node;
			expr.ccodenode = new CCodeIdentifier (decl.name);
		} else if (expr.symbol_reference.node is FormalParameter) {
			var p = (FormalParameter) expr.symbol_reference.node;
			if (p.name == "this") {
				expr.ccodenode = pub_inst;
			} else {
				if (p.type_reference.is_out || p.type_reference.reference_to_value_type) {
					expr.ccodenode = new CCodeIdentifier ("(*%s)".printf (p.name));
				} else {
					expr.ccodenode = new CCodeIdentifier (p.name);
				}
			}
		} else if (expr.symbol_reference.node is Signal) {
			var sig = (Signal) expr.symbol_reference.node;
			var cl = (DataType) sig.symbol.parent_symbol.node;
			
			if (sig.has_emitter) {
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("%s_%s".printf (cl.get_lower_case_cname (null), sig.name)));
				
				/* explicitly use strong reference as ccast
				 * gets unrefed at the end of the inner block
				 */
				ref CCodeExpression typed_pub_inst = pub_inst;

				/* cast if necessary */
				if (cl != base_type) {
					// FIXME: use C cast if debugging disabled
					var ccast = new CCodeFunctionCall (new CCodeIdentifier (cl.get_upper_case_cname (null)));
					ccast.add_argument (pub_inst);
					typed_pub_inst = ccast;
				}

				ccall.add_argument (typed_pub_inst);
				expr.ccodenode = ccall;
			} else {
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_signal_emit_by_name"));

				// FIXME: use C cast if debugging disabled
				var ccast = new CCodeFunctionCall (new CCodeIdentifier ("G_OBJECT"));
				ccast.add_argument (pub_inst);
				ccall.add_argument (ccast);

				ccall.add_argument (sig.get_canonical_cconstant ());
				
				expr.ccodenode = ccall;
			}
		}
	}
	
	public override void visit_parenthesized_expression (ParenthesizedExpression! expr) {
		expr.ccodenode = new CCodeParenthesizedExpression ((CCodeExpression) expr.inner.ccodenode);

		visit_expression (expr);
	}

	public override void visit_member_access (MemberAccess! expr) {
		CCodeExpression pub_inst = null;
		DataType base_type = null;
	
		if (expr.inner == null) {
			pub_inst = new CCodeIdentifier ("self");

			if (current_type_symbol != null) {
				/* base type is available if this is a type method */
				base_type = (DataType) current_type_symbol.node;
				
				if (!base_type.is_reference_type ()) {
					pub_inst = new CCodeIdentifier ("(*self)");
				}
			}
		} else {
			pub_inst = (CCodeExpression) expr.inner.ccodenode;

			if (expr.inner.static_type != null) {
				base_type = expr.inner.static_type.data_type;
			}
		}

		process_cmember (expr, pub_inst, base_type);

		visit_expression (expr);
	}
	
	private ref CCodeExpression! get_array_length_cexpression (Expression! array_expr, int dim) {
		bool is_out = false;
	
		if (array_expr is UnaryExpression) {
			var unary_expr = (UnaryExpression) array_expr;
			if (unary_expr.operator == UnaryOperator.OUT) {
				array_expr = unary_expr.inner;
				is_out = true;
			}
		}
		
		if (array_expr is ArrayCreationExpression) {
			var size = ((ArrayCreationExpression) array_expr).get_sizes ();
			var length_expr = (Expression) size.nth_data (dim - 1);
			return (CCodeExpression) length_expr.ccodenode;
		} else if (array_expr.symbol_reference != null) {
			if (array_expr.symbol_reference.node is FormalParameter) {
				var param = (FormalParameter) array_expr.symbol_reference.node;
				if (!param.no_array_length) {
					var length_expr = new CCodeIdentifier (get_array_length_cname (param.name, dim));
					if (is_out) {
						return new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, length_expr);
					} else {
						return length_expr;
					}
				}
			} else if (array_expr.symbol_reference.node is VariableDeclarator) {
				var decl = (VariableDeclarator) array_expr.symbol_reference.node;
				var length_expr = new CCodeIdentifier (get_array_length_cname (decl.name, dim));
				if (is_out) {
					return new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, length_expr);
				} else {
					return length_expr;
				}
			} else if (array_expr.symbol_reference.node is Field) {
				var field = (Field) array_expr.symbol_reference.node;
				if (!field.no_array_length) {
					var length_cname = get_array_length_cname (field.name, dim);

					var ma = (MemberAccess) array_expr;

					CCodeExpression pub_inst = null;
					DataType base_type = null;
					CCodeExpression length_expr = null;
				
					if (ma.inner == null) {
						pub_inst = new CCodeIdentifier ("self");

						if (current_type_symbol != null) {
							/* base type is available if this is a type method */
							base_type = (DataType) current_type_symbol.node;
						}
					} else {
						pub_inst = (CCodeExpression) ma.inner.ccodenode;

						if (ma.inner.static_type != null) {
							base_type = ma.inner.static_type.data_type;
						}
					}

					if (field.instance) {
						ref CCodeExpression typed_inst;
						if (field.symbol.parent_symbol.node != base_type) {
							// FIXME: use C cast if debugging disabled
							typed_inst = new CCodeFunctionCall (new CCodeIdentifier (((DataType) field.symbol.parent_symbol.node).get_upper_case_cname (null)));
							((CCodeFunctionCall) typed_inst).add_argument (pub_inst);
						} else {
							typed_inst = pub_inst;
						}
						ref CCodeExpression inst;
						if (field.access == MemberAccessibility.PRIVATE) {
							inst = new CCodeMemberAccess.pointer (typed_inst, "priv");
						} else {
							inst = typed_inst;
						}
						if (((DataType) field.symbol.parent_symbol.node).is_reference_type ()) {
							length_expr = new CCodeMemberAccess.pointer (inst, length_cname);
						} else {
							length_expr = new CCodeMemberAccess (inst, length_cname);
						}
					} else {
						length_expr = new CCodeIdentifier (length_cname);
					}

					if (is_out) {
						return new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, length_expr);
					} else {
						return length_expr;
					}
				}
			}
		}
		
		/* if we reach this point we were not able to get the explicit length of the array
		 * this is not allowed for an array of non-reference-type structs
		 */
		if (((Array)array_expr.static_type.data_type).element_type is Struct) {
			var s = (Struct)((Array)array_expr.static_type.data_type).element_type;
			if (!s.is_reference_type ()) {
				array_expr.error = true;
				Report.error (array_expr.source_reference, "arrays of value-type structs with no explicit length parameter are not supported");
			}
		}
		
		if (!is_out) {
			return new CCodeConstant ("-1");
		} else {
			return new CCodeConstant ("NULL");
		}
	}

	public override void visit_end_invocation_expression (InvocationExpression! expr) {
		var ccall = new CCodeFunctionCall ((CCodeExpression) expr.call.ccodenode);
		
		Method m = null;
		List<weak FormalParameter> params;
		
		if (!(expr.call is MemberAccess)) {
			expr.error = true;
			Report.error (expr.source_reference, "unsupported method invocation");
			return;
		}
		
		var ma = (MemberAccess) expr.call;
		
		if (expr.call.symbol_reference.node is Invokable) {
			var i = (Invokable) expr.call.symbol_reference.node;
			params = i.get_parameters ();
			
			if (i is Method) {
				m = (Method) i;
			} else if (i is Signal) {
				ccall = (CCodeFunctionCall) expr.call.ccodenode;
			}
		}
		
		if (m is ArrayResizeMethod) {
			var array = (Array) m.symbol.parent_symbol.node;
			ccall.add_argument (new CCodeIdentifier (array.get_cname ()));
		}
		
		/* explicitly use strong reference as ccall gets unrefed
		 * at end of inner block
		 */
		ref CCodeExpression instance;
		if (m != null && m.instance) {
			var base_method = m;
			if (m.base_interface_method != null) {
				base_method = m.base_interface_method;
			} else if (m.base_method != null) {
				base_method = m.base_method;
			}

			var req_cast = false;
			if (ma.inner == null) {
				instance = new CCodeIdentifier ("self");
				/* require casts for overriden and inherited methods */
				req_cast = m.overrides || m.base_interface_method != null || (m.symbol.parent_symbol != current_type_symbol);
			} else {
				instance = (CCodeExpression) ma.inner.ccodenode;
				/* reqiure casts if the type of the used instance is
				 * different than the type which declared the method */
				req_cast = base_method.symbol.parent_symbol.node != ma.inner.static_type.data_type;
			}
			
			if (m.instance_by_reference && (ma.inner != null || m.symbol.parent_symbol != current_type_symbol)) {
				instance = new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, instance);
			}
			
			if (req_cast && ((DataType) m.symbol.parent_symbol.node).is_reference_type ()) {
				// FIXME: use C cast if debugging disabled
				var ccall = new CCodeFunctionCall (new CCodeIdentifier (((DataType) base_method.symbol.parent_symbol.node).get_upper_case_cname (null)));
				ccall.add_argument (instance);
				instance = ccall;
			}
			
			if (!m.instance_last) {
				ccall.add_argument (instance);
			}
		}
		
		bool ellipsis = false;
		
		var i = 1;
		weak List<weak FormalParameter> params_it = params;
		foreach (Expression arg in expr.get_argument_list ()) {
			/* explicitly use strong reference as ccall gets
			 * unrefed at end of inner block
			 */
			ref CCodeExpression cexpr = (CCodeExpression) arg.ccodenode;
			if (params_it != null) {
				var param = (FormalParameter) params_it.data;
				ellipsis = param.ellipsis;
				if (!ellipsis) {
					if (param.type_reference.data_type != null
					    && param.type_reference.data_type.is_reference_type ()
					    && arg.static_type.data_type != null) {
						if (!param.no_array_length && param.type_reference.data_type is Array) {
							var arr = (Array) param.type_reference.data_type;
							for (int dim = 1; dim <= arr.rank; dim++) {
								ccall.add_argument (get_array_length_cexpression (arg, dim));
							}
						}
						if (param.type_reference.data_type != arg.static_type.data_type) {
							// FIXME: use C cast if debugging disabled
							var ccall = new CCodeFunctionCall (new CCodeIdentifier (param.type_reference.data_type.get_upper_case_cname (null)));
							ccall.add_argument (cexpr);
							cexpr = ccall;
						}
					} else if (param.type_reference.data_type is Callback) {
						cexpr = new CCodeCastExpression (cexpr, param.type_reference.data_type.get_cname ());
					} else if (param.type_reference.data_type == null
					           && arg.static_type.data_type is Struct) {
						/* convert integer to pointer if this is a generic method parameter */
						var st = (Struct) arg.static_type.data_type;
						if (st == bool_type.data_type || st.is_integer_type ()) {
							var cconv = new CCodeFunctionCall (new CCodeIdentifier ("GINT_TO_POINTER"));
							cconv.add_argument (cexpr);
							cexpr = cconv;
						}
					}
				}
			}
					
			ccall.add_argument (cexpr);
			i++;
			
			if (params_it != null) {
				params_it = params_it.next;
			}
		}
		while (params_it != null) {
			var param = (FormalParameter) params_it.data;
			
			if (param.ellipsis) {
				ellipsis = true;
				break;
			}
			
			if (param.default_expression == null) {
				Report.error (expr.source_reference, "no default expression for argument %d".printf (i));
				return;
			}
			
			/* evaluate default expression here as the code
			 * generator might not have visited the formal
			 * parameter yet */
			param.default_expression.accept (this);
		
			if (!param.no_array_length && param.type_reference != null &&
			    param.type_reference.data_type is Array) {
				var arr = (Array) param.type_reference.data_type;
				for (int dim = 1; dim <= arr.rank; dim++) {
					ccall.add_argument (get_array_length_cexpression (param.default_expression, dim));
				}
			}

			ccall.add_argument ((CCodeExpression) param.default_expression.ccodenode);
			i++;
		
			params_it = params_it.next;
		}
		
		if (m != null && m.instance && m.instance_last) {
			ccall.add_argument (instance);
		} else if (ellipsis) {
			/* ensure variable argument list ends with NULL
			 * except when using printf-style arguments */
			if (m == null || !m.printf_format) {
				ccall.add_argument (new CCodeConstant ("NULL"));
			}
		}
		
		if (m != null && m.instance && m.returns_modified_pointer) {
			expr.ccodenode = new CCodeAssignment (instance, ccall);
		} else {
			/* cast pointer to actual type if this is a generic method return value */
			if (m != null && m.return_type.type_parameter != null && expr.static_type.data_type != null) {
				if (expr.static_type.data_type is Struct) {
					var st = (Struct) expr.static_type.data_type;
					if (st == bool_type.data_type || st.is_integer_type ()) {
						var cconv = new CCodeFunctionCall (new CCodeIdentifier ("GPOINTER_TO_INT"));
						cconv.add_argument (ccall);
						ccall = cconv;
					}
				}
			}

			expr.ccodenode = ccall;
		
			visit_expression (expr);
		}
		
		if (m is ArrayResizeMethod) {
			var ccomma = new CCodeCommaExpression ();
			ccomma.append_expression ((CCodeExpression) expr.ccodenode);
			// FIXME: size expression must not be evaluated twice at runtime (potential side effects)
			var new_size = (CCodeExpression) ((CodeNode) expr.get_argument_list ().data).ccodenode;
			ccomma.append_expression (new CCodeAssignment (get_array_length_cexpression (ma.inner, 1), new_size));
			expr.ccodenode = ccomma;
		}
	}
	
	public override void visit_element_access (ElementAccess! expr)
	{
		List<weak Expression> indices = expr.get_indices ();
		int rank = indices.length ();
		
		if (rank == 1) {
			/* FIXME: had to add Expression cast due to possible compiler bug */
			expr.ccodenode = new CCodeElementAccess ((CCodeExpression)expr.container.ccodenode, (CCodeExpression)((Expression)indices.first ().data).ccodenode);
		} else {
			expr.error = true;
			Report.error (expr.source_reference, "Arrays with more then one dimension are not supported yet");
			return;
		}

		visit_expression (expr);
	}

	public override void visit_base_access (BaseAccess! expr) {
		expr.ccodenode = new InstanceCast (new CCodeIdentifier ("self"), expr.static_type.data_type);
	}

	public override void visit_postfix_expression (PostfixExpression! expr) {
		MemberAccess ma = find_property_access (expr.inner);
		if (ma != null) {
			// property postfix expression
			var prop = (Property) ma.symbol_reference.node;
			
			var ccomma = new CCodeCommaExpression ();
			
			// assign current value to temp variable
			var temp_decl = get_temp_variable_declarator (prop.type_reference);
			temp_vars.prepend (temp_decl);
			ccomma.append_expression (new CCodeAssignment (new CCodeIdentifier (temp_decl.name), (CCodeExpression) expr.inner.ccodenode));
			
			// increment/decrement property
			var op = expr.increment ? CCodeBinaryOperator.PLUS : CCodeBinaryOperator.MINUS;
			var cexpr = new CCodeBinaryExpression (op, new CCodeIdentifier (temp_decl.name), new CCodeConstant ("1"));
			var ccall = get_property_set_call (prop, ma, cexpr);
			ccomma.append_expression (ccall);
			
			// return previous value
			ccomma.append_expression (new CCodeIdentifier (temp_decl.name));
			
			expr.ccodenode = ccomma;
			return;
		}
	
		var op = expr.increment ? CCodeUnaryOperator.POSTFIX_INCREMENT : CCodeUnaryOperator.POSTFIX_DECREMENT;
	
		expr.ccodenode = new CCodeUnaryExpression (op, (CCodeExpression) expr.inner.ccodenode);
		
		visit_expression (expr);
	}
	
	private MemberAccess find_property_access (Expression! expr) {
		if (expr is ParenthesizedExpression) {
			var pe = (ParenthesizedExpression) expr;
			return find_property_access (pe.inner);
		}
	
		if (!(expr is MemberAccess)) {
			return null;
		}
		
		var ma = (MemberAccess) expr;
		if (ma.symbol_reference.node is Property) {
			return ma;
		}
		
		return null;
	}
	
	private ref CCodeExpression get_ref_expression (Expression! expr) {
		/* (temp = expr, temp == NULL ? NULL : ref (temp))
		 *
		 * can be simplified to
		 * ref (expr)
		 * if static type of expr is non-null
		 */
		 
		if (expr.static_type.data_type == null &&
		    expr.static_type.type_parameter != null) {
			expr.error = true;
			Report.error (expr.source_reference, "Missing generics support for memory management");
			return null;
		}
	
		string ref_function;
		if (expr.static_type.data_type.is_reference_counting ()) {
			ref_function = expr.static_type.data_type.get_ref_function ();
		} else {
			if (expr.static_type.data_type != string_type.data_type) {
				// duplicating non-reference counted structs may cause side-effects (and performance issues)
				Report.warning (expr.source_reference, "duplicating %s instance, use weak variable or explicitly invoke copy method".printf (expr.static_type.data_type.name));
			}
			ref_function = expr.static_type.data_type.get_dup_function ();
		}
	
		var ccall = new CCodeFunctionCall (new CCodeIdentifier (ref_function));

		if (expr.static_type.non_null) {
			ccall.add_argument ((CCodeExpression) expr.ccodenode);
			
			return ccall;
		} else {
			var decl = get_temp_variable_declarator (expr.static_type, false);
			temp_vars.prepend (decl);

			var ctemp = new CCodeIdentifier (decl.name);
			
			var cisnull = new CCodeBinaryExpression (CCodeBinaryOperator.EQUALITY, ctemp, new CCodeConstant ("NULL"));
			
			ccall.add_argument (ctemp);
			
			var ccomma = new CCodeCommaExpression ();
			ccomma.append_expression (new CCodeAssignment (ctemp, (CCodeExpression) expr.ccodenode));

			if (ref_function == "g_list_copy") {
				bool is_ref = false;
				bool is_class = false;
				bool is_interface = false;

				foreach (TypeReference type_arg in expr.static_type.get_type_arguments ()) {
					is_ref |= type_arg.takes_ownership;
					is_class |= type_arg.data_type is Class;
					is_interface |= type_arg.data_type is Interface;
				}
			
				if (is_ref && (is_class || is_interface)) {
					var crefcall = new CCodeFunctionCall (new CCodeIdentifier ("g_list_foreach"));

					crefcall.add_argument (ctemp);
					crefcall.add_argument (new CCodeIdentifier ("(GFunc) g_object_ref"));
					crefcall.add_argument (new CCodeConstant ("NULL"));

					ccomma.append_expression (crefcall);
				}
			}

			ccomma.append_expression (new CCodeConditionalExpression (cisnull, new CCodeConstant ("NULL"), ccall));

			return ccomma;
		}
	}
	
	private void visit_expression (Expression! expr) {
		if (expr.static_type != null &&
		    expr.static_type.transfers_ownership &&
		    expr.static_type.floating_reference) {
			/* constructor of GInitiallyUnowned subtype
			 * returns floating reference, sink it
			 */
			var csink = new CCodeFunctionCall (new CCodeIdentifier ("g_object_ref_sink"));
			csink.add_argument ((CCodeExpression) expr.ccodenode);
			
			expr.ccodenode = csink;
		}
	
		if (expr.ref_leaked) {
			var decl = get_temp_variable_declarator (expr.static_type);
			temp_vars.prepend (decl);
			temp_ref_vars.prepend (decl);
			expr.ccodenode = new CCodeParenthesizedExpression (new CCodeAssignment (new CCodeIdentifier (decl.name), (CCodeExpression) expr.ccodenode));
		} else if (expr.ref_missing) {
			expr.ccodenode = get_ref_expression (expr);
		}
	}

	public override void visit_end_object_creation_expression (ObjectCreationExpression! expr) {
		if (expr.symbol_reference == null) {
			// no creation method
			if (expr.type_reference.data_type is Class) {
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_object_new"));
				
				ccall.add_argument (new CCodeConstant (expr.type_reference.data_type.get_type_id ()));

				ccall.add_argument (new CCodeConstant ("NULL"));
				
				expr.ccodenode = ccall;
			} else if (expr.type_reference.data_type == list_type ||
			           expr.type_reference.data_type == slist_type) {
				// NULL is an empty list
				expr.ccodenode = new CCodeConstant ("NULL");
			} else {
				var ccall = new CCodeFunctionCall (new CCodeIdentifier ("g_new0"));
				
				ccall.add_argument (new CCodeConstant (expr.type_reference.data_type.get_cname ()));
				
				ccall.add_argument (new CCodeConstant ("1"));
				
				expr.ccodenode = ccall;
			}
		} else {
			// use creation method
			var m = (Method) expr.symbol_reference.node;
			var params = m.get_parameters ();

			var ccall = new CCodeFunctionCall (new CCodeIdentifier (m.get_cname ()));

			bool ellipsis = false;

			int i = 1;
			weak List<weak FormalParameter> params_it = params;
			foreach (Expression arg in expr.get_argument_list ()) {
				/* explicitly use strong reference as ccall gets
				 * unrefed at end of inner block
				 */
				ref CCodeExpression cexpr = (CCodeExpression) arg.ccodenode;
				if (params_it != null) {
					var param = (FormalParameter) params_it.data;
					ellipsis = param.ellipsis;
					if (!param.ellipsis
					    && param.type_reference.data_type != null
					    && param.type_reference.data_type.is_reference_type ()
					    && arg.static_type.data_type != null
					    && param.type_reference.data_type != arg.static_type.data_type) {
						// FIXME: use C cast if debugging disabled
						var ccall = new CCodeFunctionCall (new CCodeIdentifier (param.type_reference.data_type.get_upper_case_cname (null)));
						ccall.add_argument (cexpr);
						cexpr = ccall;
					}
				}
			
				ccall.add_argument (cexpr);
				i++;
				
				if (params_it != null) {
					params_it = params_it.next;
				}
			}
			while (params_it != null) {
				var param = (FormalParameter) params_it.data;
				
				if (param.ellipsis) {
					ellipsis = true;
					break;
				}
				
				if (param.default_expression == null) {
					Report.error (expr.source_reference, "no default expression for argument %d".printf (i));
					return;
				}
				
				/* evaluate default expression here as the code
				 * generator might not have visited the formal
				 * parameter yet */
				param.default_expression.accept (this);
			
				ccall.add_argument ((CCodeExpression) param.default_expression.ccodenode);
				i++;
			
				params_it = params_it.next;
			}

			if (ellipsis) {
				// ensure variable argument list ends with NULL
				ccall.add_argument (new CCodeConstant ("NULL"));
			}
			
			expr.ccodenode = ccall;
		}
			
		visit_expression (expr);
	}

	public override void visit_typeof_expression (TypeofExpression! expr) {
		expr.ccodenode = new CCodeIdentifier (expr.type_reference.data_type.get_type_id ());
	}

	public override void visit_unary_expression (UnaryExpression! expr) {
		CCodeUnaryOperator op;
		if (expr.operator == UnaryOperator.PLUS) {
			op = CCodeUnaryOperator.PLUS;
		} else if (expr.operator == UnaryOperator.MINUS) {
			op = CCodeUnaryOperator.MINUS;
		} else if (expr.operator == UnaryOperator.LOGICAL_NEGATION) {
			op = CCodeUnaryOperator.LOGICAL_NEGATION;
		} else if (expr.operator == UnaryOperator.BITWISE_COMPLEMENT) {
			op = CCodeUnaryOperator.BITWISE_COMPLEMENT;
		} else if (expr.operator == UnaryOperator.INCREMENT) {
			op = CCodeUnaryOperator.PREFIX_INCREMENT;
		} else if (expr.operator == UnaryOperator.DECREMENT) {
			op = CCodeUnaryOperator.PREFIX_DECREMENT;
		} else if (expr.operator == UnaryOperator.REF) {
			op = CCodeUnaryOperator.ADDRESS_OF;
		} else if (expr.operator == UnaryOperator.OUT) {
			op = CCodeUnaryOperator.ADDRESS_OF;
		}
		expr.ccodenode = new CCodeUnaryExpression (op, (CCodeExpression) expr.inner.ccodenode);
		
		visit_expression (expr);
	}

	public override void visit_cast_expression (CastExpression! expr) {
		if (expr.type_reference.data_type is Class || expr.type_reference.data_type is Interface) {
			// GObject cast
			expr.ccodenode = new InstanceCast ((CCodeExpression) expr.inner.ccodenode, expr.type_reference.data_type);
		} else {
			expr.ccodenode = new CCodeCastExpression ((CCodeExpression) expr.inner.ccodenode, expr.type_reference.get_cname ());
		}
		
		visit_expression (expr);
	}
	
	public override void visit_pointer_indirection (PointerIndirection! expr) {
		expr.ccodenode = new CCodeUnaryExpression (CCodeUnaryOperator.POINTER_INDIRECTION, (CCodeExpression) expr.inner.ccodenode);
	}

	public override void visit_addressof_expression (AddressofExpression! expr) {
		expr.ccodenode = new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, (CCodeExpression) expr.inner.ccodenode);
	}

	public override void visit_binary_expression (BinaryExpression! expr) {
		CCodeBinaryOperator op;
		if (expr.operator == BinaryOperator.PLUS) {
			op = CCodeBinaryOperator.PLUS;
		} else if (expr.operator == BinaryOperator.MINUS) {
			op = CCodeBinaryOperator.MINUS;
		} else if (expr.operator == BinaryOperator.MUL) {
			op = CCodeBinaryOperator.MUL;
		} else if (expr.operator == BinaryOperator.DIV) {
			op = CCodeBinaryOperator.DIV;
		} else if (expr.operator == BinaryOperator.MOD) {
			op = CCodeBinaryOperator.MOD;
		} else if (expr.operator == BinaryOperator.SHIFT_LEFT) {
			op = CCodeBinaryOperator.SHIFT_LEFT;
		} else if (expr.operator == BinaryOperator.SHIFT_RIGHT) {
			op = CCodeBinaryOperator.SHIFT_RIGHT;
		} else if (expr.operator == BinaryOperator.LESS_THAN) {
			op = CCodeBinaryOperator.LESS_THAN;
		} else if (expr.operator == BinaryOperator.GREATER_THAN) {
			op = CCodeBinaryOperator.GREATER_THAN;
		} else if (expr.operator == BinaryOperator.LESS_THAN_OR_EQUAL) {
			op = CCodeBinaryOperator.LESS_THAN_OR_EQUAL;
		} else if (expr.operator == BinaryOperator.GREATER_THAN_OR_EQUAL) {
			op = CCodeBinaryOperator.GREATER_THAN_OR_EQUAL;
		} else if (expr.operator == BinaryOperator.EQUALITY) {
			op = CCodeBinaryOperator.EQUALITY;
		} else if (expr.operator == BinaryOperator.INEQUALITY) {
			op = CCodeBinaryOperator.INEQUALITY;
		} else if (expr.operator == BinaryOperator.BITWISE_AND) {
			op = CCodeBinaryOperator.BITWISE_AND;
		} else if (expr.operator == BinaryOperator.BITWISE_OR) {
			op = CCodeBinaryOperator.BITWISE_OR;
		} else if (expr.operator == BinaryOperator.BITWISE_XOR) {
			op = CCodeBinaryOperator.BITWISE_XOR;
		} else if (expr.operator == BinaryOperator.AND) {
			op = CCodeBinaryOperator.AND;
		} else if (expr.operator == BinaryOperator.OR) {
			op = CCodeBinaryOperator.OR;
		}
		
		var cleft = (CCodeExpression) expr.left.ccodenode;
		var cright = (CCodeExpression) expr.right.ccodenode;
		
		if (expr.operator == BinaryOperator.EQUALITY ||
		    expr.operator == BinaryOperator.INEQUALITY) {
			if (expr.left.static_type != null && expr.right.static_type != null &&
			    expr.left.static_type.data_type is Class && expr.right.static_type.data_type is Class) {
				var left_cl = (Class) expr.left.static_type.data_type;
				var right_cl = (Class) expr.right.static_type.data_type;
				
				if (left_cl != right_cl) {
					if (left_cl.is_subtype_of (right_cl)) {
						cleft = new InstanceCast (cleft, right_cl);
					} else if (right_cl.is_subtype_of (left_cl)) {
						cright = new InstanceCast (cright, left_cl);
					}
				}
			}
		}
		
		expr.ccodenode = new CCodeBinaryExpression (op, cleft, cright);
		
		visit_expression (expr);
	}

	public override void visit_type_check (TypeCheck! expr) {
		var ccheck = new CCodeFunctionCall (new CCodeIdentifier (expr.type_reference.data_type.get_upper_case_cname ("IS_")));
		ccheck.add_argument ((CCodeExpression) expr.expression.ccodenode);
		expr.ccodenode = ccheck;
	}

	public override void visit_conditional_expression (ConditionalExpression! expr) {
		expr.ccodenode = new CCodeConditionalExpression ((CCodeExpression) expr.condition.ccodenode, (CCodeExpression) expr.true_expression.ccodenode, (CCodeExpression) expr.false_expression.ccodenode);
	}

	public override void visit_end_lambda_expression (LambdaExpression! l) {
		l.ccodenode = new CCodeIdentifier (l.method.get_cname ());
	}

	public override void visit_end_assignment (Assignment! a) {
		MemberAccess ma = null;
		
		if (a.left is MemberAccess) {
			ma = (MemberAccess)a.left;
		}

		if (a.left.symbol_reference != null && a.left.symbol_reference.node is Property) {
			var prop = (Property) a.left.symbol_reference.node;
			
			if (ma.inner == null && a.parent_node is Statement &&
			    ((Statement) a.parent_node).construction) {
				// this property is used as a construction parameter
				var cpointer = new CCodeIdentifier ("__params_it");
				
				var ccomma = new CCodeCommaExpression ();
				// set name in array for current parameter
				var cnamemember = new CCodeMemberAccess.pointer (cpointer, "name");
				var cnameassign = new CCodeAssignment (cnamemember, prop.get_canonical_cconstant ());
				ccomma.append_expression (cnameassign);
				
				var gvaluearg = new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, new CCodeMemberAccess.pointer (cpointer, "value"));
				
				// initialize GValue in array for current parameter
				var cvalueinit = new CCodeFunctionCall (new CCodeIdentifier ("g_value_init"));
				cvalueinit.add_argument (gvaluearg);
				cvalueinit.add_argument (new CCodeIdentifier (prop.type_reference.data_type.get_type_id ()));
				ccomma.append_expression (cvalueinit);
				
				// set GValue for current parameter
				var cvalueset = new CCodeFunctionCall (get_value_setter_function (prop.type_reference));
				cvalueset.add_argument (gvaluearg);
				cvalueset.add_argument ((CCodeExpression) a.right.ccodenode);
				ccomma.append_expression (cvalueset);
				
				// move pointer to next parameter in array
				ccomma.append_expression (new CCodeUnaryExpression (CCodeUnaryOperator.POSTFIX_INCREMENT, cpointer));
				
				a.ccodenode = ccomma;
			} else {
				ref CCodeExpression cexpr = (CCodeExpression) a.right.ccodenode;
				
				if (!prop.no_accessor_method
				    && prop.type_reference.data_type != null
				    && prop.type_reference.data_type.is_reference_type ()
				    && a.right.static_type.data_type != null
				    && prop.type_reference.data_type != a.right.static_type.data_type) {
					/* cast is necessary */
					var ccast = new CCodeFunctionCall (new CCodeIdentifier (prop.type_reference.data_type.get_upper_case_cname (null)));
					ccast.add_argument (cexpr);
					cexpr = ccast;
				}
				
				if (a.operator != AssignmentOperator.SIMPLE) {
					CCodeBinaryOperator cop;
					if (a.operator == AssignmentOperator.BITWISE_OR) {
						cop = CCodeBinaryOperator.BITWISE_OR;
					} else if (a.operator == AssignmentOperator.BITWISE_AND) {
						cop = CCodeBinaryOperator.BITWISE_AND;
					} else if (a.operator == AssignmentOperator.BITWISE_XOR) {
						cop = CCodeBinaryOperator.BITWISE_XOR;
					} else if (a.operator == AssignmentOperator.ADD) {
						cop = CCodeBinaryOperator.PLUS;
					} else if (a.operator == AssignmentOperator.SUB) {
						cop = CCodeBinaryOperator.MINUS;
					} else if (a.operator == AssignmentOperator.MUL) {
						cop = CCodeBinaryOperator.MUL;
					} else if (a.operator == AssignmentOperator.DIV) {
						cop = CCodeBinaryOperator.DIV;
					} else if (a.operator == AssignmentOperator.PERCENT) {
						cop = CCodeBinaryOperator.MOD;
					} else if (a.operator == AssignmentOperator.SHIFT_LEFT) {
						cop = CCodeBinaryOperator.SHIFT_LEFT;
					} else if (a.operator == AssignmentOperator.SHIFT_RIGHT) {
						cop = CCodeBinaryOperator.SHIFT_RIGHT;
					}
					cexpr = new CCodeBinaryExpression (cop, (CCodeExpression) a.left.ccodenode, new CCodeParenthesizedExpression (cexpr));
				}
				
				var ccall = get_property_set_call (prop, ma, cexpr);
				
				// assignments are expressions, so return the current property value
				var ccomma = new CCodeCommaExpression ();
				ccomma.append_expression (ccall); // update property
				ccomma.append_expression ((CCodeExpression) ma.ccodenode); // current property value
				
				a.ccodenode = ccomma;
			}
		} else if (a.left.symbol_reference != null && a.left.symbol_reference.node is Signal) {
			var sig = (Signal) a.left.symbol_reference.node;
			
			var m = (Method) a.right.symbol_reference.node;

			string connect_func;
			bool disconnect = false;

			if (a.operator == AssignmentOperator.ADD) {
				connect_func = "g_signal_connect_object";
				if (!m.instance) {
					connect_func = "g_signal_connect";
				}
			} else if (a.operator == AssignmentOperator.SUB) {
				connect_func = "g_signal_handlers_disconnect_matched";
				disconnect = true;
			} else {
				a.error = true;
				Report.error (a.source_reference, "Specified compound assignment type for signals not supported.");
				return;
			}

			var ccall = new CCodeFunctionCall (new CCodeIdentifier (connect_func));
		
			if (ma.inner != null) {
				ccall.add_argument ((CCodeExpression) ma.inner.ccodenode);
			} else {
				ccall.add_argument (new CCodeIdentifier ("self"));
			}

			if (!disconnect) {
				ccall.add_argument (sig.get_canonical_cconstant ());
			} else {
				ccall.add_argument (new CCodeConstant ("G_SIGNAL_MATCH_ID | G_SIGNAL_MATCH_FUNC | G_SIGNAL_MATCH_DATA"));
				
				// get signal id
				var ccomma = new CCodeCommaExpression ();
				var temp_decl = get_temp_variable_declarator (uint_type);
				temp_vars.prepend (temp_decl);
				var parse_call = new CCodeFunctionCall (new CCodeIdentifier ("g_signal_parse_name"));
				parse_call.add_argument (sig.get_canonical_cconstant ());
				var decl_type = (DataType) sig.symbol.parent_symbol.node;
				parse_call.add_argument (new CCodeIdentifier (decl_type.get_type_id ()));
				parse_call.add_argument (new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, new CCodeIdentifier (temp_decl.name)));
				parse_call.add_argument (new CCodeConstant ("NULL"));
				parse_call.add_argument (new CCodeConstant ("FALSE"));
				ccomma.append_expression (parse_call);
				ccomma.append_expression (new CCodeIdentifier (temp_decl.name));
				
				ccall.add_argument (ccomma);

				ccall.add_argument (new CCodeConstant ("0"));
				ccall.add_argument (new CCodeConstant ("NULL"));
			}

			ccall.add_argument (new CCodeCastExpression (new CCodeIdentifier (m.get_cname ()), "GCallback"));

			if (m.instance) {
				if (a.right is MemberAccess) {
					var right_ma = (MemberAccess) a.right;
					if (right_ma.inner != null) {
						ccall.add_argument ((CCodeExpression) right_ma.inner.ccodenode);
					} else {
						ccall.add_argument (new CCodeIdentifier ("self"));
					}
				} else if (a.right is LambdaExpression) {
					ccall.add_argument (new CCodeIdentifier ("self"));
				}
				if (!disconnect) {
					ccall.add_argument (new CCodeConstant ("0"));
				}
			} else {
				ccall.add_argument (new CCodeConstant ("NULL"));
			}
			
			a.ccodenode = ccall;
		} else {
			/* explicitly use strong reference as ccast gets
			 * unrefed at end of inner block
			 */
			ref CCodeExpression rhs = (CCodeExpression) a.right.ccodenode;
			
			if (a.left.static_type.data_type != null
			    && a.right.static_type.data_type != null
			    && a.left.static_type.data_type.is_reference_type ()
			    && a.right.static_type.data_type != a.left.static_type.data_type) {
				var ccast = new CCodeFunctionCall (new CCodeIdentifier (a.left.static_type.data_type.get_upper_case_cname (null)));
				ccast.add_argument (rhs);
				rhs = ccast;
			}
			
			bool unref_old = (memory_management && a.left.static_type.takes_ownership);
			bool array = false;
			if (a.left.static_type.data_type is Array) {
				array = !(get_array_length_cexpression (a.left, 1) is CCodeConstant);
			}
			
			if (unref_old || array) {
				var ccomma = new CCodeCommaExpression ();
				
				var temp_decl = get_temp_variable_declarator (a.left.static_type);
				temp_vars.prepend (temp_decl);
				ccomma.append_expression (new CCodeAssignment (new CCodeIdentifier (temp_decl.name), rhs));
				if (unref_old) {
					/* unref old value */
					ccomma.append_expression (get_unref_expression ((CCodeExpression) a.left.ccodenode, a.left.static_type));
				}
				
				if (array) {
					var lhs_array_len = get_array_length_cexpression (a.left, 1);
					var rhs_array_len = get_array_length_cexpression (a.right, 1);
					ccomma.append_expression (new CCodeAssignment (lhs_array_len, rhs_array_len));
				}
				
				ccomma.append_expression (new CCodeIdentifier (temp_decl.name));
				
				rhs = ccomma;
			}
			
			var cop = CCodeAssignmentOperator.SIMPLE;
			if (a.operator == AssignmentOperator.BITWISE_OR) {
				cop = CCodeAssignmentOperator.BITWISE_OR;
			} else if (a.operator == AssignmentOperator.BITWISE_AND) {
				cop = CCodeAssignmentOperator.BITWISE_AND;
			} else if (a.operator == AssignmentOperator.BITWISE_XOR) {
				cop = CCodeAssignmentOperator.BITWISE_XOR;
			} else if (a.operator == AssignmentOperator.ADD) {
				cop = CCodeAssignmentOperator.ADD;
			} else if (a.operator == AssignmentOperator.SUB) {
				cop = CCodeAssignmentOperator.SUB;
			} else if (a.operator == AssignmentOperator.MUL) {
				cop = CCodeAssignmentOperator.MUL;
			} else if (a.operator == AssignmentOperator.DIV) {
				cop = CCodeAssignmentOperator.DIV;
			} else if (a.operator == AssignmentOperator.PERCENT) {
				cop = CCodeAssignmentOperator.PERCENT;
			} else if (a.operator == AssignmentOperator.SHIFT_LEFT) {
				cop = CCodeAssignmentOperator.SHIFT_LEFT;
			} else if (a.operator == AssignmentOperator.SHIFT_RIGHT) {
				cop = CCodeAssignmentOperator.SHIFT_RIGHT;
			}
		
			a.ccodenode = new CCodeAssignment ((CCodeExpression) a.left.ccodenode, rhs, cop);
		}
	}
	
	private ref CCodeFunctionCall get_property_set_call (Property! prop, MemberAccess! ma, CCodeExpression! cexpr) {
		var cl = (Class) prop.symbol.parent_symbol.node;
		var set_func = "g_object_set";
		
		if (!prop.no_accessor_method) {
			set_func = "%s_set_%s".printf (cl.get_lower_case_cname (null), prop.name);
		}
		
		var ccall = new CCodeFunctionCall (new CCodeIdentifier (set_func));

		/* target instance is first argument */
		ref CCodeExpression instance;
		var req_cast = false;

		if (ma.inner == null) {
			instance = new CCodeIdentifier ("self");
			/* require casts for inherited properties */
			req_cast = (prop.symbol.parent_symbol != current_type_symbol);
		} else {
			instance = (CCodeExpression) ma.inner.ccodenode;
			/* require casts if the type of the used instance is
			 * different than the type which declared the property */
			req_cast = prop.symbol.parent_symbol.node != ma.inner.static_type.data_type;
		}
		
		if (req_cast && ((DataType) prop.symbol.parent_symbol.node).is_reference_type ()) {
			var ccast = new CCodeFunctionCall (new CCodeIdentifier (((DataType) prop.symbol.parent_symbol.node).get_upper_case_cname (null)));
			ccast.add_argument (instance);
			instance = ccast;
		}

		ccall.add_argument (instance);

		if (prop.no_accessor_method) {
			/* property name is second argument of g_object_set */
			ccall.add_argument (prop.get_canonical_cconstant ());
		}
			
		ccall.add_argument (cexpr);
		
		if (prop.no_accessor_method) {
			ccall.add_argument (new CCodeConstant ("NULL"));
		}

		return ccall;
	}
}
