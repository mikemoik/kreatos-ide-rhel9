// test/run.sh: links onnxruntime and OpenDDS, uses an IDL-generated type
#include <onnxruntime_cxx_api.h>

#include <dds/DCPS/Service_Participant.h>
#include <dds/Version.h>

#include "MsgTypeSupportImpl.h"

#include <iostream>

int main(int argc, char* argv[]) {
  std::cout << "onnxruntime " << Ort::GetVersionString() << "\n";
  Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "kide");

  DDS::DomainParticipantFactory_var dpf = TheParticipantFactoryWithArgs(argc, argv);
  Kide::Msg msg;
  msg.id = 1;
  msg.text = "hello";
  Kide::MsgTypeSupport_var ts = new Kide::MsgTypeSupportImpl;
  std::cout << "OpenDDS " << DDS_VERSION << ", type " << ts->get_type_name() << ", msg " << msg.text.in() << "\n";
  TheServiceParticipant->shutdown();
  return 0;
}
