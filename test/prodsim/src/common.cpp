#include "common.h"

#include <dds/DCPS/DomainParticipantImpl.h>
#include <dds/DCPS/GuidConverter.h>
#include <dds/DCPS/Marked_Default_Qos.h>
#include <dds/DCPS/Service_Participant.h>
// RTPS discovery and transport: these headers pull the libraries in and
// register them (as in OpenDDS's Messenger example)
#include <dds/DCPS/RTPS/RtpsDiscovery.h>
#include <dds/DCPS/transport/rtps_udp/RtpsUdp.h>

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <unistd.h>
#include <vector>

namespace prodsim {

std::string prefix_dir()
{
  char buf[4096];
  const ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
  if (n <= 0) throw std::runtime_error("readlink /proc/self/exe failed");
  std::string exe(buf, n);
  std::string bin = exe.substr(0, exe.find_last_of('/'));
  return bin.substr(0, bin.find_last_of('/'));
}

std::string run_dir()
{
  const char* dir = std::getenv("PRODSIM_RUN_DIR");
  return dir && *dir ? dir : ".";
}

std::string ior_file()
{
  return run_dir() + "/prodsim-control.ior";
}

DDS::DomainParticipant_ptr create_participant(int argc, char* argv[])
{
  std::string config = prefix_dir() + "/share/prodsim/rtps.ini";
  std::vector<char*> args(argv, argv + argc);
  args.push_back(const_cast<char*>("-DCPSConfigFile"));
  args.push_back(&config[0]);
  int n = int(args.size());
  args.push_back(nullptr);

  DDS::DomainParticipantFactory_var dpf = TheParticipantFactoryWithArgs(n, args.data());
  DDS::DomainParticipant_var participant = dpf->create_participant(
    DOMAIN, PARTICIPANT_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
  if (!participant) throw std::runtime_error("create_participant failed");
  return participant._retn();
}

void delete_participant(DDS::DomainParticipant_ptr participant)
{
  participant->delete_contained_entities();
  TheParticipantFactory->delete_participant(participant);
  TheServiceParticipant->shutdown();
}

std::string participant_guid(DDS::DomainParticipant_ptr participant)
{
  auto* impl = dynamic_cast<OpenDDS::DCPS::DomainParticipantImpl*>(participant);
  if (!impl) return "?";
  const OpenDDS::DCPS::GUID_t guid = impl->get_id();
  return OpenDDS::DCPS::LogGuid(guid).c_str();
}

CORBA::ORB_ptr init_orb(int argc, char* argv[])
{
  std::vector<char*> args(argv, argv + argc);
  int n = int(args.size());
  args.push_back(nullptr);
  return CORBA::ORB_init(n, args.data(), "prodsim");
}

ProdSim::TrackerControl_ptr connect_control(CORBA::ORB_ptr orb, int timeout_s)
{
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(timeout_s);
  std::string ior;
  while (true) {
    std::ifstream in(ior_file());
    if (in && std::getline(in, ior) && ior.rfind("IOR:", 0) == 0) break;
    if (std::chrono::steady_clock::now() > deadline) {
      throw std::runtime_error("no IOR in " + ior_file() + " (is prodsim-control running?)");
    }
    sleep_ms(100);
  }
  CORBA::Object_var obj = orb->string_to_object(ior.c_str());
  ProdSim::TrackerControl_var control = ProdSim::TrackerControl::_narrow(obj.in());
  if (CORBA::is_nil(control.in())) throw std::runtime_error("IOR is not a TrackerControl");
  return control._retn();
}

bool control_running(ProdSim::TrackerControl_ptr control)
{
  try {
    return control->running();
  } catch (const CORBA::Exception&) {
    return false;
  }
}

void sleep_ms(int ms)
{
  std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

} // namespace prodsim
