// prodsim-tracker: subscribes to ProdSim::Detection, keeps one track per
// tile, publishes ProdSim::Track and, once prodsim-control is stopped, writes
// $PRODSIM_RUN_DIR/prodsim-report.json with RapidJSON.
#include "common.h"

#include "TrackTypeSupportImpl.h"

#include <dds/DCPS/Marked_Default_Qos.h>

#include <rapidjson/prettywriter.h>
#include <rapidjson/stringbuffer.h>

#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>

int main(int argc, char* argv[])
{
  try {
    CORBA::ORB_var orb = prodsim::init_orb(argc, argv);
    ProdSim::TrackerControl_var control = prodsim::connect_control(orb.in());

    DDS::DomainParticipant_var participant = prodsim::create_participant(argc, argv);
    const std::string guid = prodsim::participant_guid(participant.in());
    std::cout << "prodsim-tracker: participant " << guid << std::endl;

    ProdSim::DetectionTypeSupport_var dts = new ProdSim::DetectionTypeSupportImpl;
    dts->register_type(participant.in(), "");
    CORBA::String_var dtype = dts->get_type_name();
    DDS::Topic_var dtopic = participant->create_topic(
      prodsim::DETECTION_TOPIC, dtype.in(), TOPIC_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::Subscriber_var sub = participant->create_subscriber(
      SUBSCRIBER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::DataReaderQos rqos;
    sub->get_default_datareader_qos(rqos);
    rqos.reliability.kind = DDS::RELIABLE_RELIABILITY_QOS;
    rqos.history.kind = DDS::KEEP_ALL_HISTORY_QOS;
    DDS::DataReader_var dr = sub->create_datareader(
      dtopic.in(), rqos, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    ProdSim::DetectionDataReader_var reader = ProdSim::DetectionDataReader::_narrow(dr.in());

    ProdSim::TrackTypeSupport_var tts = new ProdSim::TrackTypeSupportImpl;
    tts->register_type(participant.in(), "");
    CORBA::String_var ttype = tts->get_type_name();
    DDS::Topic_var ttopic = participant->create_topic(
      prodsim::TRACK_TOPIC, ttype.in(), TOPIC_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::Publisher_var pub = participant->create_publisher(
      PUBLISHER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::DataWriter_var dw = pub->create_datawriter(
      ttopic.in(), DATAWRITER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    ProdSim::TrackDataWriter_var writer = ProdSim::TrackDataWriter::_narrow(dw.in());
    if (!reader || !writer) throw std::runtime_error("narrow failed");

    std::map<CORBA::ULong, ProdSim::Track> tracks;
    unsigned long detections = 0, last_frame = 0;
    int idle_ms = 0;
    while (true) {
      ProdSim::Detection d;
      DDS::SampleInfo info;
      bool got = false;
      while (reader->take_next_sample(d, info) == DDS::RETCODE_OK) {
        if (!info.valid_data) continue;
        got = true;
        ++detections;
        last_frame = std::max<unsigned long>(last_frame, d.frame);
        auto it = tracks.find(d.tile);
        if (it == tracks.end()) {
          // IDL structs (classic C++ mapping) are not zero-initialized
          ProdSim::Track fresh;
          fresh.track_id = d.tile;
          fresh.hits = 0;
          fresh.last_frame = 0;
          fresh.x = fresh.y = 0;
          fresh.confidence = 0;
          it = tracks.emplace(d.tile, fresh).first;
        }
        ProdSim::Track& t = it->second;
        // smoothed position and confidence
        const double a = t.hits ? 0.3 : 1.0;
        t.x = (1 - a) * t.x + a * d.x;
        t.y = (1 - a) * t.y + a * d.y;
        t.confidence = float((1 - a) * t.confidence + a * d.confidence);
        t.hits += 1;
        t.last_frame = d.frame;
        writer->write(t, DDS::HANDLE_NIL);
      }
      if (got) continue;
      prodsim::sleep_ms(50);
      idle_ms += 50;
      if (idle_ms >= 200) {
        idle_ms = 0;
        if (!prodsim::control_running(control.in())) break;
      }
    }

    rapidjson::StringBuffer buf;
    rapidjson::PrettyWriter<rapidjson::StringBuffer> json(buf);
    json.StartObject();
    json.Key("participant");
    json.String(guid.c_str());
    json.Key("detections");
    json.Uint64(detections);
    json.Key("last_frame");
    json.Uint64(last_frame);
    json.Key("tracks");
    json.StartArray();
    for (const auto& kv : tracks) {
      const ProdSim::Track& t = kv.second;
      json.StartObject();
      json.Key("id");
      json.Uint(t.track_id);
      json.Key("hits");
      json.Uint(t.hits);
      json.Key("lon");
      json.Double(t.x);
      json.Key("lat");
      json.Double(t.y);
      json.Key("confidence");
      json.Double(t.confidence);
      json.EndObject();
    }
    json.EndArray();
    json.EndObject();
    const std::string path = prodsim::run_dir() + "/prodsim-report.json";
    std::ofstream(path) << buf.GetString() << "\n";
    std::cout << "prodsim-tracker: " << detections << " detections, " << tracks.size()
              << " tracks, report in " << path << std::endl;

    prodsim::delete_participant(participant.in());
    orb->destroy();
  } catch (const CORBA::Exception& e) {
    e._tao_print_exception("prodsim-tracker");
    return 1;
  } catch (const std::exception& e) {
    std::cerr << "prodsim-tracker: " << e.what() << std::endl;
    return 1;
  }
  return 0;
}
