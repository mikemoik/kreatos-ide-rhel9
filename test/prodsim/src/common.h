// prodsim: helpers shared by the programs (paths, DDS participant, the CORBA
// control object)
#ifndef PRODSIM_COMMON_H
#define PRODSIM_COMMON_H

#include "ControlC.h"

#include <dds/DdsDcpsDomainC.h>

#include <string>

namespace prodsim {

constexpr DDS::DomainId_t DOMAIN = 42;
constexpr const char* DETECTION_TOPIC = "prodsim_detections";
constexpr const char* TRACK_TOPIC = "prodsim_tracks";

// install prefix: the directory above the running binary's bin/
std::string prefix_dir();
// $PRODSIM_RUN_DIR, else the current directory: IOR file, report, screenshot
std::string run_dir();
std::string ior_file();

// TheParticipantFactoryWithArgs with -DCPSConfigFile PREFIX/share/prodsim/rtps.ini
// (RTPS discovery, no DCPSInfoRepo), then a participant in DOMAIN
DDS::DomainParticipant_ptr create_participant(int argc, char* argv[]);
void delete_participant(DDS::DomainParticipant_ptr participant);
// the participant's GUID (OpenDDS::DCPS::GUID_t, formerly RepoId) as text
std::string participant_guid(DDS::DomainParticipant_ptr participant);

// the ORB and the TrackerControl object from the IOR file (waits up to
// timeout_s for prodsim-control to write it)
CORBA::ORB_ptr init_orb(int argc, char* argv[]);
ProdSim::TrackerControl_ptr connect_control(CORBA::ORB_ptr orb, int timeout_s = 20);
// false when stopped or when prodsim-control is gone
bool control_running(ProdSim::TrackerControl_ptr control);

void sleep_ms(int ms);

} // namespace prodsim

#endif
