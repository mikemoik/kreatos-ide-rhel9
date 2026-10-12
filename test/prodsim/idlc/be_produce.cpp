// prodsim-idlc backend: walks the AST the TAO_IDL front end built and writes
// <file>.schema.json (structs with their fields, interfaces with their
// operations). Stands in for the prod IDL compiler's code generator: what
// matters for kide is that it compiles against TAO_IDL's headers and links
// libTAO_IDL_FE + libACE, like prod.
#include "be_extern.h"
#include "be_util.h"

#include "ast_field.h"
#include "ast_generator.h"
#include "ast_interface.h"
#include "ast_module.h"
#include "ast_operation.h"
#include "ast_root.h"
#include "ast_structure.h"
#include "drv_extern.h"
#include "global_extern.h"
#include "idl_defines.h"
#include "nr_extern.h"
#include "utl_identifier.h"
#include "utl_string.h"

#include <ace/Log_Msg.h>
#include <ace/OS_NS_string.h>

#include <fstream>
#include <sstream>
#include <string>
#include <vector>

BE_GlobalData* be_global = nullptr;

void BE_GlobalData::parse_args(long& i, char** av)
{
  if (ACE_OS::strcmp(av[i], "-o") == 0 && av[i + 1]) {
    output_dir = av[++i];
    return;
  }
  ACE_ERROR((LM_ERROR, "prodsim-idlc: unknown option %C\n", av[i]));
  idl_global->parse_args_exit(1);
}

int BE_init(int&, ACE_TCHAR*[])
{
  ACE_NEW_RETURN(be_global, BE_GlobalData, -1);
  idl_global->default_idl_version_ = IDL_VERSION_4;
  return 0;
}

void BE_post_init(char*[], long)
{
  // the DDS annotations Track.idl uses (as opendds_idl declares them)
  idl_global->eval("@annotation key { boolean value default TRUE; };\n");
  idl_global->eval("@annotation topic { string name default \"\"; string platform default \"*\"; };\n");
}

void BE_version()
{
  ACE_DEBUG((LM_DEBUG, "prodsim-idlc (JSON schema backend)\n"));
}

void BE_abort() {}
void BE_cleanup() {}

void be_util::prep_be_arg(char*) {}
void be_util::arg_post_proc() {}

void be_util::usage()
{
  ACE_DEBUG((LM_DEBUG, " -o <dir>               output directory (default: .)\n"));
}

AST_Generator* be_util::generator_init()
{
  AST_Generator* gen = nullptr;
  ACE_NEW_RETURN(gen, AST_Generator, nullptr);
  return gen;
}

namespace {

std::string quoted(const char* s)
{
  std::string out = "\"";
  for (; *s; ++s) {
    if (*s == '"' || *s == '\\') out += '\\';
    out += *s;
  }
  return out + "\"";
}

void walk(UTL_Scope* scope, std::vector<std::string>& entries)
{
  for (UTL_ScopeActiveIterator it(scope, UTL_Scope::IK_decls); !it.is_done(); it.next()) {
    AST_Decl* d = it.item();
    if (d->imported()) continue; // from an #included file
    std::ostringstream e;
    switch (d->node_type()) {
    case AST_Decl::NT_module:
      walk(DeclAsScope(d), entries);
      break;
    case AST_Decl::NT_struct: {
      AST_Structure* s = dynamic_cast<AST_Structure*>(d);
      e << "    {\"kind\": \"struct\", \"name\": " << quoted(s->full_name())
        << ", \"repoId\": " << quoted(s->repoID()) << ", \"fields\": [";
      ACE_Unbounded_Queue_Iterator<AST_Field*> fi(s->fields());
      const char* sep = "";
      for (AST_Field** f = nullptr; fi.next(f); fi.advance()) {
        e << sep << "{\"name\": " << quoted((*f)->local_name()->get_string())
          << ", \"type\": " << quoted((*f)->field_type()->full_name()) << "}";
        sep = ", ";
      }
      e << "]}";
      entries.push_back(e.str());
      break;
    }
    case AST_Decl::NT_interface: {
      e << "    {\"kind\": \"interface\", \"name\": " << quoted(d->full_name())
        << ", \"repoId\": " << quoted(d->repoID()) << ", \"operations\": [";
      const char* sep = "";
      for (UTL_ScopeActiveIterator oi(DeclAsScope(d), UTL_Scope::IK_decls); !oi.is_done(); oi.next()) {
        AST_Operation* op = dynamic_cast<AST_Operation*>(oi.item());
        if (!op) continue;
        e << sep << "{\"name\": " << quoted(op->local_name()->get_string())
          << ", \"returns\": " << quoted(op->return_type()->full_name())
          << ", \"arguments\": " << op->argument_count() << "}";
        sep = ", ";
      }
      e << "]}";
      entries.push_back(e.str());
      break;
    }
    default:
      break;
    }
  }
}

} // namespace

void BE_produce()
{
  std::string src = idl_global->main_filename()->get_string();
  std::string stem = src.substr(src.find_last_of('/') + 1);
  stem = stem.substr(0, stem.rfind('.'));
  const std::string path = be_global->output_dir + "/" + stem + ".schema.json";

  std::vector<std::string> entries;
  walk(idl_global->root(), entries);

  std::ofstream out(path);
  out << "{\n  \"source\": " << quoted(stem.c_str()) << ",\n  \"types\": [\n";
  for (size_t i = 0; i < entries.size(); ++i) {
    out << entries[i] << (i + 1 < entries.size() ? ",\n" : "\n");
  }
  out << "  ]\n}\n";
  if (!out) {
    ACE_ERROR((LM_ERROR, "prodsim-idlc: cannot write %C\n", path.c_str()));
    idl_global->set_err_count(idl_global->err_count() + 1);
    return;
  }
  ACE_DEBUG((LM_DEBUG, "prodsim-idlc: wrote %C (%d types)\n", path.c_str(), int(entries.size())));
}
