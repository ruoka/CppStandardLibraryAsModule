import std;

using namespace std::literals;

int main()
{
    std::cout << "Hello World! "s + "YEE!"s << std::endl;

    auto map = std::map<int,int>{};
    map[1] = 2;

    return 0;
}
