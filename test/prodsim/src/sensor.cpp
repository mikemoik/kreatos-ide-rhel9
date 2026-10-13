// prodsim-sensor: reads a georeferenced image with GDAL, scores each 32x32
// tile with the onnxruntime model and publishes the tiles above the threshold
// (from prodsim-control over CORBA) as ProdSim::Detection over DDS, frame
// after frame, until prodsim-control is stopped.
//   prodsim-sensor --make-sample FILE.tif   write the sample GeoTIFF and exit
//   prodsim-sensor [--image FILE] [--rate HZ]   any format GDAL reads
// The GeoTIFF needs the dist's GDAL (build-dist.sh): RHEL9's gdal-libs
// (AppStream) is a minimal build without the GTiff driver.
#include "common.h"
#include "ort_model.h"

#include "TrackTypeSupportImpl.h"

#include <dds/DCPS/Marked_Default_Qos.h>

#include <cpl_conv.h>
#include <gdal.h>
#include <ogr_srs_api.h>

#include <cmath>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr int SIZE = 256; // sample image: SIZE x SIZE pixels
constexpr int TILE = 32;

std::vector<uint8_t> sample_pixels();

void make_sample(const std::string& path)
{
  GDALDriverH driver = GDALGetDriverByName("GTiff");
  if (!driver) throw std::runtime_error("GDAL has no GTiff driver (RHEL's gdal-libs instead of the dist's?)");
  GDALDatasetH ds = GDALCreate(driver, path.c_str(), SIZE, SIZE, 1, GDT_Byte, nullptr);
  if (!ds) throw std::runtime_error("cannot create " + path);
  std::vector<uint8_t> pixels = sample_pixels();
  if (GDALRasterIO(GDALGetRasterBand(ds, 1), GF_Write, 0, 0, SIZE, SIZE, pixels.data(), SIZE, SIZE,
                   GDT_Byte, 0, 0) != CE_None) {
    throw std::runtime_error("cannot write the pixels to " + path);
  }

  // 0.001 degree pixels near Munich, WGS 84
  double gt[6] = {11.50, 0.001, 0, 48.20, 0, -0.001};
  GDALSetGeoTransform(ds, gt);
  OGRSpatialReferenceH srs = OSRNewSpatialReference(nullptr);
  OSRImportFromEPSG(srs, 4326);
  char* wkt = nullptr;
  OSRExportToWkt(srs, &wkt);
  GDALSetProjection(ds, wkt);
  CPLFree(wkt);
  OSRDestroySpatialReference(srs);
  GDALClose(ds);
  std::cout << "prodsim-sensor: wrote " << path << " (GeoTIFF, " << SIZE << "x" << SIZE
            << ", EPSG:4326)" << std::endl;
}

std::vector<uint8_t> sample_pixels()
{
  // dark background with three bright blobs: the "targets"
  const double blobs[3][2] = {{60, 70}, {180, 90}, {120, 200}};
  std::vector<uint8_t> pixels(SIZE * SIZE);
  for (int y = 0; y < SIZE; ++y) {
    for (int x = 0; x < SIZE; ++x) {
      double v = 25 + 10 * std::sin(x * 0.3) * std::cos(y * 0.2);
      for (const auto& b : blobs) {
        const double d2 = (x - b[0]) * (x - b[0]) + (y - b[1]) * (y - b[1]);
        v += 220 * std::exp(-d2 / (2 * 14.0 * 14.0));
      }
      pixels[y * SIZE + x] = uint8_t(std::min(255.0, v));
    }
  }
  return pixels;
}

struct Image {
  int width = 0, height = 0;
  double gt[6] = {};
  std::vector<uint8_t> pixels;
};

Image load(const std::string& path)
{
  GDALDatasetH ds = GDALOpen(path.c_str(), GA_ReadOnly);
  if (!ds) throw std::runtime_error("GDAL cannot open " + path);
  Image img;
  img.width = GDALGetRasterXSize(ds);
  img.height = GDALGetRasterYSize(ds);
  GDALGetGeoTransform(ds, img.gt);
  img.pixels.resize(size_t(img.width) * img.height);
  if (GDALRasterIO(GDALGetRasterBand(ds, 1), GF_Read, 0, 0, img.width, img.height,
                   img.pixels.data(), img.width, img.height, GDT_Byte, 0, 0) != CE_None) {
    throw std::runtime_error("cannot read " + path);
  }
  GDALClose(ds);
  return img;
}

} // namespace

int main(int argc, char* argv[])
{
  GDALAllRegister();
  std::string image = prodsim::run_dir() + "/sample.tif";
  double rate = 20;
  try {
    for (int i = 1; i < argc; ++i) {
      const std::string a = argv[i];
      if (a == "--make-sample" && i + 1 < argc) {
        make_sample(argv[i + 1]);
        return 0;
      }
      if (a == "--image" && i + 1 < argc) image = argv[++i];
      if (a == "--rate" && i + 1 < argc) rate = std::stod(argv[++i]);
    }

    const Image img = load(image);
    prodsim::OrtModel model(prodsim::prefix_dir() + "/share/prodsim/tile_sigmoid.onnx");
    std::cout << "prodsim-sensor: " << image << " " << img.width << "x" << img.height
              << ", onnxruntime " << prodsim::OrtModel::version() << ", GDAL "
              << GDALVersionInfo("RELEASE_NAME") << std::endl;

    CORBA::ORB_var orb = prodsim::init_orb(argc, argv);
    ProdSim::TrackerControl_var control = prodsim::connect_control(orb.in());

    DDS::DomainParticipant_var participant = prodsim::create_participant(argc, argv);
    ProdSim::DetectionTypeSupport_var ts = new ProdSim::DetectionTypeSupportImpl;
    ts->register_type(participant.in(), "");
    CORBA::String_var type_name = ts->get_type_name();
    DDS::Topic_var topic = participant->create_topic(
      prodsim::DETECTION_TOPIC, type_name.in(), TOPIC_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::Publisher_var pub = participant->create_publisher(
      PUBLISHER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::DataWriter_var dw = pub->create_datawriter(
      topic.in(), DATAWRITER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    ProdSim::DetectionDataWriter_var writer = ProdSim::DetectionDataWriter::_narrow(dw.in());
    if (!writer) throw std::runtime_error("DetectionDataWriter narrow failed");
    std::cout << "prodsim-sensor: participant " << prodsim::participant_guid(participant.in()) << std::endl;

    const int tiles_x = img.width / TILE, tiles_y = img.height / TILE;
    unsigned long frame = 0, published = 0;
    float threshold = control->threshold();
    while (prodsim::control_running(control.in())) {
      // tile means, modulated per frame so the scores move around the threshold
      std::vector<float> input;
      for (int ty = 0; ty < tiles_y; ++ty) {
        for (int tx = 0; tx < tiles_x; ++tx) {
          double sum = 0;
          for (int y = ty * TILE; y < (ty + 1) * TILE; ++y) {
            for (int x = tx * TILE; x < (tx + 1) * TILE; ++x) sum += img.pixels[size_t(y) * img.width + x];
          }
          const double mean = sum / (TILE * TILE) + 15 * std::sin(frame * 0.15 + tx + 2 * ty);
          input.push_back(float(mean / 255.0 * 12.0 - 4.0));
        }
      }
      const std::vector<float> scores = model.run(input);

      if (frame % 20 == 0) threshold = control->threshold();
      for (size_t t = 0; t < scores.size(); ++t) {
        if (scores[t] < threshold) continue;
        const int tx = int(t) % tiles_x, ty = int(t) / tiles_x;
        ProdSim::Detection d;
        d.tile = CORBA::ULong(t);
        d.frame = frame;
        d.x = img.gt[0] + (tx + 0.5) * TILE * img.gt[1];
        d.y = img.gt[3] + (ty + 0.5) * TILE * img.gt[5];
        d.confidence = scores[t];
        if (writer->write(d, DDS::HANDLE_NIL) == DDS::RETCODE_OK) ++published;
      }
      ++frame;
      prodsim::sleep_ms(int(1000 / rate));
    }
    std::cout << "prodsim-sensor: " << frame << " frames, " << published << " detections published" << std::endl;

    prodsim::delete_participant(participant.in());
    orb->destroy();
  } catch (const CORBA::Exception& e) {
    e._tao_print_exception("prodsim-sensor");
    return 1;
  } catch (const std::exception& e) {
    std::cerr << "prodsim-sensor: " << e.what() << std::endl;
    return 1;
  }
  return 0;
}
