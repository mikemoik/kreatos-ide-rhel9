// prodsim-control: TAO CORBA server for ProdSim::TrackerControl. Writes its
// IOR to $PRODSIM_RUN_DIR/prodsim-control.ior and serves until 3 s after
// stop(), so the other programs still see running() == false.
#include "common.h"

#include "ControlS.h"

#include <ace/Time_Value.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <iostream>

namespace {

class ControlImpl : public virtual POA_ProdSim::TrackerControl {
public:
  ::CORBA::Float threshold() override { return threshold_; }
  void set_threshold(::CORBA::Float value) override { threshold_ = value; }
  ::CORBA::Boolean running() override { return running_; }
  void stop() override
  {
    if (running_.exchange(false)) std::cout << "prodsim-control: stop" << std::endl;
  }

  float threshold_ = 0.7f;
  std::atomic<bool> running_{true};
};

} // namespace

int main(int argc, char* argv[])
{
  try {
    CORBA::ORB_var orb = prodsim::init_orb(argc, argv);
    CORBA::Object_var obj = orb->resolve_initial_references("RootPOA");
    PortableServer::POA_var poa = PortableServer::POA::_narrow(obj.in());
    PortableServer::POAManager_var manager = poa->the_POAManager();
    manager->activate();

    ControlImpl servant;
    for (int i = 1; i + 1 < argc; ++i) {
      if (std::string(argv[i]) == "--threshold") servant.threshold_ = std::stof(argv[++i]);
    }
    PortableServer::ObjectId_var oid = poa->activate_object(&servant);
    CORBA::Object_var ref = poa->id_to_reference(oid.in());
    CORBA::String_var ior = orb->object_to_string(ref.in());

    // write-then-rename: readers never see a half-written IOR
    const std::string path = prodsim::ior_file();
    std::ofstream(path + ".tmp") << ior.in() << "\n";
    std::rename((path + ".tmp").c_str(), path.c_str());
    std::cout << "prodsim-control: serving, threshold " << servant.threshold_
              << ", IOR in " << path << std::endl;

    auto stopped_at = std::chrono::steady_clock::time_point{};
    while (true) {
      ACE_Time_Value tv(0, 100000);
      orb->perform_work(tv);
      if (servant.running_) continue;
      const auto now = std::chrono::steady_clock::now();
      if (stopped_at == decltype(stopped_at){}) stopped_at = now;
      if (now - stopped_at > std::chrono::seconds(3)) break;
    }

    std::remove(path.c_str());
    poa->destroy(true, true);
    orb->destroy();
  } catch (const CORBA::Exception& e) {
    e._tao_print_exception("prodsim-control");
    return 1;
  } catch (const std::exception& e) {
    std::cerr << "prodsim-control: " << e.what() << std::endl;
    return 1;
  }
  std::cout << "prodsim-control: done" << std::endl;
  return 0;
}
