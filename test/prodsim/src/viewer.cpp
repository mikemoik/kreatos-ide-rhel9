// prodsim-viewer: OpenGL 3.3 (GLFW + GLEW) window with a spinning pyramid
// driven by the ProdSim::Track samples it receives over DDS: more tracks spin
// it faster, higher confidence turns it from blue to red. When it is done
// (window closed, or --frames reached) it stops the pipeline through
// prodsim-control.
//   prodsim-viewer                         interactive, until the window is closed
//   prodsim-viewer --frames N --screenshot FILE.ppm
//                                          wait for the first track, render N
//                                          frames, save the last one, exit (tests)
#include <GL/glew.h>
#include <GLFW/glfw3.h>

#include "common.h"

#include "TrackTypeSupportImpl.h"

#include <dds/DCPS/Marked_Default_Qos.h>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using Mat4 = std::array<float, 16>; // column-major

Mat4 mul(const Mat4& a, const Mat4& b)
{
  Mat4 r{};
  for (int c = 0; c < 4; ++c)
    for (int row = 0; row < 4; ++row)
      for (int k = 0; k < 4; ++k) r[c * 4 + row] += a[k * 4 + row] * b[c * 4 + k];
  return r;
}

Mat4 perspective(float fovy, float aspect, float near, float far)
{
  const float f = 1.0f / std::tan(fovy / 2);
  Mat4 m{};
  m[0] = f / aspect;
  m[5] = f;
  m[10] = (far + near) / (near - far);
  m[11] = -1;
  m[14] = 2 * far * near / (near - far);
  return m;
}

Mat4 translate(float x, float y, float z)
{
  Mat4 m{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1};
  return m;
}

Mat4 rotate_y(float a)
{
  Mat4 m{std::cos(a), 0, -std::sin(a), 0, 0, 1, 0, 0, std::sin(a), 0, std::cos(a), 0, 0, 0, 0, 1};
  return m;
}

Mat4 rotate_x(float a)
{
  Mat4 m{1, 0, 0, 0, 0, std::cos(a), std::sin(a), 0, 0, -std::sin(a), std::cos(a), 0, 0, 0, 0, 1};
  return m;
}

const char* VERTEX_SHADER = R"(#version 330 core
layout(location = 0) in vec3 pos;
layout(location = 1) in float shade;
uniform mat4 mvp;
out float v_shade;
void main() { gl_Position = mvp * vec4(pos, 1.0); v_shade = shade; }
)";

const char* FRAGMENT_SHADER = R"(#version 330 core
in float v_shade;
uniform vec3 color;
out vec4 frag;
void main() { frag = vec4(color * v_shade, 1.0); }
)";

GLuint compile(GLenum type, const char* src)
{
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, nullptr);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[1024];
    glGetShaderInfoLog(s, sizeof log, nullptr, log);
    throw std::runtime_error(std::string("shader: ") + log);
  }
  return s;
}

// x, y, z, shade per vertex: four sides and the base (two triangles)
std::vector<float> pyramid()
{
  const float apex[3] = {0, 1, 0};
  const float base[4][3] = {{-1, -0.6f, 1}, {1, -0.6f, 1}, {1, -0.6f, -1}, {-1, -0.6f, -1}};
  const float side_shade[4] = {1.0f, 0.8f, 0.6f, 0.75f};
  std::vector<float> v;
  auto add = [&v](const float* p, float shade) { v.insert(v.end(), {p[0], p[1], p[2], shade}); };
  for (int i = 0; i < 4; ++i) {
    add(base[i], side_shade[i]);
    add(base[(i + 1) % 4], side_shade[i]);
    add(apex, side_shade[i]);
  }
  const int tris[2][3] = {{0, 2, 1}, {0, 3, 2}};
  for (const auto& t : tris)
    for (int i : t) add(base[i], 0.4f);
  return v;
}

void save_ppm(const std::string& path, int w, int h)
{
  std::vector<unsigned char> px(size_t(w) * h * 3);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RGB, GL_UNSIGNED_BYTE, px.data());
  std::ofstream out(path, std::ios::binary);
  out << "P6\n" << w << " " << h << "\n255\n";
  for (int y = h - 1; y >= 0; --y) out.write(reinterpret_cast<char*>(&px[size_t(y) * w * 3]), w * 3);
}

} // namespace

int main(int argc, char* argv[])
{
  int frames = 0; // 0: interactive
  std::string screenshot;
  for (int i = 1; i + 1 < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--frames") frames = std::stoi(argv[++i]);
    else if (a == "--screenshot") screenshot = argv[++i];
  }

  try {
    CORBA::ORB_var orb = prodsim::init_orb(argc, argv);
    ProdSim::TrackerControl_var control = prodsim::connect_control(orb.in());

    DDS::DomainParticipant_var participant = prodsim::create_participant(argc, argv);
    ProdSim::TrackTypeSupport_var ts = new ProdSim::TrackTypeSupportImpl;
    ts->register_type(participant.in(), "");
    CORBA::String_var type_name = ts->get_type_name();
    DDS::Topic_var topic = participant->create_topic(
      prodsim::TRACK_TOPIC, type_name.in(), TOPIC_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::Subscriber_var sub = participant->create_subscriber(
      SUBSCRIBER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    DDS::DataReader_var dr = sub->create_datareader(
      topic.in(), DATAREADER_QOS_DEFAULT, 0, OpenDDS::DCPS::DEFAULT_STATUS_MASK);
    ProdSim::TrackDataReader_var reader = ProdSim::TrackDataReader::_narrow(dr.in());
    if (!reader) throw std::runtime_error("TrackDataReader narrow failed");

    if (!glfwInit()) throw std::runtime_error("glfwInit failed (no display? set DISPLAY)");
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    const int width = 640, height = 480;
    GLFWwindow* window = glfwCreateWindow(width, height, "prodsim-viewer", nullptr, nullptr);
    if (!window) throw std::runtime_error("glfwCreateWindow failed (OpenGL 3.3 core available?)");
    glfwMakeContextCurrent(window);
    glfwSwapInterval(frames ? 0 : 1);
    glewExperimental = GL_TRUE;
    if (glewInit() != GLEW_OK) throw std::runtime_error("glewInit failed");
    glGetError(); // glewInit may leave GL_INVALID_ENUM on core profiles
    std::cout << "prodsim-viewer: " << glGetString(GL_RENDERER) << ", OpenGL " << glGetString(GL_VERSION)
              << ", GLEW " << glewGetString(GLEW_VERSION) << ", GLFW " << glfwGetVersionString() << std::endl;

    GLuint prog = glCreateProgram();
    glAttachShader(prog, compile(GL_VERTEX_SHADER, VERTEX_SHADER));
    glAttachShader(prog, compile(GL_FRAGMENT_SHADER, FRAGMENT_SHADER));
    glLinkProgram(prog);
    const GLint mvp_loc = glGetUniformLocation(prog, "mvp");
    const GLint color_loc = glGetUniformLocation(prog, "color");

    const std::vector<float> verts = pyramid();
    GLuint vao, vbo;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(float), verts.data(), GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, 4 * sizeof(float), reinterpret_cast<void*>(3 * sizeof(float)));
    glEnableVertexAttribArray(1);
    glEnable(GL_DEPTH_TEST);

    std::map<CORBA::ULong, float> confidence; // per track
    float angle = 0;
    int rendered = 0;
    long frame_no = 0;
    bool counting = false;
    const auto start = std::chrono::steady_clock::now();
    auto last = start;
    while (!glfwWindowShouldClose(window)) {
      ProdSim::Track t;
      DDS::SampleInfo info;
      while (reader->take_next_sample(t, info) == DDS::RETCODE_OK) {
        if (info.valid_data) confidence[t.track_id] = t.confidence;
      }
      float mean = 0;
      for (const auto& kv : confidence) mean += kv.second;
      if (!confidence.empty()) mean /= confidence.size();

      const auto now = std::chrono::steady_clock::now();
      const float dt = frames ? 1.0f / 60 : std::chrono::duration<float>(now - last).count();
      last = now;
      angle += dt * (0.6f + 0.15f * confidence.size());

      int fb_w, fb_h;
      glfwGetFramebufferSize(window, &fb_w, &fb_h);
      glViewport(0, 0, fb_w, fb_h);
      glClearColor(0.08f, 0.08f, 0.10f, 1);
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
      const Mat4 mvp = mul(perspective(0.9f, float(fb_w) / fb_h, 0.1f, 20),
                           mul(translate(0, 0, -4), mul(rotate_x(0.35f), rotate_y(angle))));
      glUseProgram(prog);
      glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, mvp.data());
      // blue (no tracks / low confidence) to red (high confidence)
      glUniform3f(color_loc, 0.2f + 0.8f * mean, 0.4f - 0.1f * mean, 1.0f - 0.9f * mean);
      glBindVertexArray(vao);
      glDrawArrays(GL_TRIANGLES, 0, GLsizei(verts.size() / 4));

      if (frames) {
        // test mode: start counting at the first track, give up after 30 s
        if (!counting && !confidence.empty()) counting = true;
        if (counting && ++rendered >= frames) {
          if (!screenshot.empty()) save_ppm(screenshot, fb_w, fb_h);
          break;
        }
        if (now - start > std::chrono::seconds(30)) throw std::runtime_error("no tracks within 30 s");
      }
      glfwSwapBuffers(window);
      glfwPollEvents();
      if (++frame_no % 30 == 0) {
        const std::string title = "prodsim-viewer: " + std::to_string(confidence.size()) + " tracks";
        glfwSetWindowTitle(window, title.c_str());
      }
      if (!frames && !prodsim::control_running(control.in())) break;
    }
    std::cout << "prodsim-viewer: " << confidence.size() << " tracks seen, mean confidence "
              << [&] { float m = 0; for (const auto& kv : confidence) m += kv.second;
                       return confidence.empty() ? 0.0f : m / confidence.size(); }()
              << (screenshot.empty() ? "" : ", screenshot " + screenshot) << std::endl;

    glfwDestroyWindow(window);
    glfwTerminate();
    control->stop();
    prodsim::delete_participant(participant.in());
    orb->destroy();
  } catch (const CORBA::Exception& e) {
    e._tao_print_exception("prodsim-viewer");
    return 1;
  } catch (const std::exception& e) {
    std::cerr << "prodsim-viewer: " << e.what() << std::endl;
    return 1;
  }
  return 0;
}
