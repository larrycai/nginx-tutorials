# Nginx 变量漫谈（一） #

Nginx 的配置文件使用的就是一门微型的编程语言，许多真实世界里的 Nginx
配置文件其实就是一个一个的小程序。当然，是不是“图灵完全的”暂且不论，至少据我观
察，它在设计上受 Perl 和 Bourne Shell 这两种语言的影响很大。
在这一点上，相比 Apache 和 Lighttpd 等其他 Web 服务器的配
置记法，不能不说算是 Nginx 的一大特色了。既然是编程语言，一般也就少不了“
变量”这种东西（当然，Haskell 这样奇怪的函数式语言除外了）。

熟悉 Perl、Bourne Shell、C/C++ 等命令式编程语言的朋友肯定
知道，变量说白了就是存放“值”的容器。而所谓“值”，在许多编程语言里，既可以是
C<3.14> 这样的数值，也可以是 C<hello world> 这样的字符串
，甚至可以是像数组、哈希表这样的复杂数据结构。然而，在 Nginx 配置中，变量
只能存放一种类型的值，因为也只存在一种类型的值，那就是字符串。

比如我们的 F<nginx.conf> 文件中有下面这一行配置：

    :nginx
    set $a "hello world";

我们使用了标准 L<ngx_rewrite> 模块的 L<ngx_rewrite/set>
配置指令对变量 C<$a> 进行了赋值操作。特别地，我们把字符串 C<hello
world> 赋给了它。

我们看到，Nginx 变量名前面有一个 C<$> 符号，这是记法上的要求。所有的
Nginx 变量在 Nginx 配置文件中引用时都须带上 C<$> 前缀。这种
表示方法和 Perl、PHP 这些语言是相似的。

虽然 C<$> 这样的变量前缀修饰会让正统的 C<Java> 和 C<C#> 程
序员不舒服，
但这种表示方法的好处也是显而易见的，那就是可以直接把变量嵌入到字符串常量中以构造
出新的字符串：

    :nginx
    set $a hello;
    set $b "$a, $a";

这里我们通过已有的 Nginx 变量 C<$a> 的值，来构造变量 C<$b>
的值，于是这两条指令顺序执行完之后，C<$a> 的值是 C<hello>，而 C<$b>
的值则是 C<hello, hello>. 这种技术在 Perl 世界里被称为“
变
量插值”（variable interpolation），它让专门的字符串拼接运
算符变得
不再那么必要。
我们在这里也不妨采用此术语。

我们来看一个比较完整的配置示例：

    :nginx
    server {
        listen 8080;

        location /test {
            set $foo hello;
            echo "foo: $foo";
        }
    }

这个例子省略了 F<nginx.conf> 配置文件中最外围的 C<http>
配置块以及 C<events> 配置块。使用 C<curl> 这个 HTTP 客
户端在命令行上请求这个 C</test> 接口，我们可
以得到

    :bash
    $ curl 'http://localhost:8080/test'
    foo: hello

这里我们使用第三方 L<ngx_echo> 模块的 L<ngx_echo/echo>
配置指令将 C<$foo> 变量的值作为当前请求的响应体输出。

我们看到，L<ngx_echo/echo> 配置指令的参数也支持“变量
插值”。不过，需要说明的是，并非所有的配置指令都支持“变量插值”。事实上，指令参
数是否允许“变量插值”，取决于该指令的实现模块。

如果我们想通过 L<ngx_echo/echo>
指令直接输出含有“美元符”（C<$>）的字符串，那么有没有办法把特殊的
C<$> 字符给转义
掉呢？答案是否定的（至少到目前最新的 Nginx 稳定版 C<1.0.10>）。
不过幸运的是，我们可以绕过这个限制，比如通过
不支持“变量插值”的模块配置指令专门构造出取值为 C<$> 的 Nginx 变量
，然后再在 L<ngx_echo/echo>
中使用这个变量。看下面这个例子：

    :nginx
    geo $dollar {
        default "$";
    }

    server {
        listen 8080;

        location /test {
            echo "This is a dollar sign: $dollar";
        }
    }

测试结果如下：

    :bash
    $ curl 'http://localhost:8080/test'
    This is a dollar sign: $

这里用到了标准模块 L<ngx_geo> 提供的配置指令 L<ngx_geo/geo>
来为变量 C<$dollar> 赋予字符串 C<"$">，这样我们在下面需要使用
美元符的地方，就直接引用我们的 C<$dollar> 变量就可以了。其实 L<ngx_geo>
模块最常规的用法是根据客户端的 IP 地址对指定的 Nginx 变量进行赋值，
这里只是借用它以便“无条件地”对我们的 C<$dollar> 变量赋予“美元符”
这个值。

在“变量插值”的上下文中，还有一种特殊情况，即当引用的变量名之后紧跟着变量名的构
成字符时（比如后跟字母、数字
以及下划线），我们就需要使用特别的记法来消除歧义，例如：

    :nginx
    server {
        listen 8080;

        location /test {
            set $first "hello ";
            echo "${first}world";
        }
    }

这里，我们在 L<ngx_echo/echo> 配置指令的参数值中引用变量 C<$first>
的时候，后面紧跟着 C<world> 这个单词，所以如果直接写作 C<"$firstworld">
则 Nginx “变量插值”计算引擎会将之识别为引用了变量 C<$firstworld>.
为了解决这个难题，Nginx 的字符串记法支持使用花括号在 C<$> 之后把变量
名围起来，比如这里的 C<${first}>. 上面这个例子的输出是：

    :bash
    $ curl 'http://localhost:8080/test
    hello world

L<ngx_rewrite/set> 指令（以及前面提到的 L<ngx_geo/geo>
指令）不仅有赋值的功能，它还有创建 Nginx 变量的副作用，即当作
为赋值对象的变量尚不存在时，它会自动创建该变量。比如在上面这个例子中，如
果 C<$a> 这个变量尚未创建，则 C<set> 指令会自动创建 C<$a>
这个用户变量。如果我们不创建就直接使用它的值，则会报错。例如

    :nginx
    ? server {
    ?     listen 8080;
    ?
    ?     location /bad {
    ?         echo $foo;
    ?     }
    ? }

此时 Nginx 服务器会拒绝加载配置:

    [emerg] unknown "foo" variable

是的，我们甚至都无法启动服务！

有趣的是，Nginx 变量的创建和赋值操作发生在全然不同的时间阶段。Nginx
变量的创建只能发生在 Nginx 配置加载的时候，或者说 Nginx 启动的时候
；而赋值操作则只会发生在请求实际处理的时候。这意味着不创建而直接使用变量会导致启
动失败，同时也意味着我们无法
在请求处理时动态地创建新的 Nginx 变量。

Nginx 变量一旦创建，其变量名的可见范围就是整个 Nginx 配置，甚至可以
跨越不同虚拟
主机的 C<server> 配置块。我们来看一个例子：

    :nginx
    server {
        listen 8080;

        location /foo {
            echo "foo = [$foo]";
        }

        location /bar {
            set $foo 32;
            echo "foo = [$foo]";
        }
    }

这里我们在 C<location /bar> 中用 C<set> 指令创建了变量
C<$foo>，于是在整个配置文件中这个变量都是可见的，因此我们可以在 C<location
/foo> 中直接引用这个变量而不用担心 Nginx 会报错。

下面是在命令行上用 C<curl> 工具访问这两个接口的结果：

    :bash
    $ curl 'http://localhost:8080/foo'
    foo = []

    $ curl 'http://localhost:8080/bar'
    foo = [32]

    $ curl 'http://localhost:8080/foo'
    foo = []

从这个例子我们可以看到，C<set> 指令因为是在 C<location /bar>
中使用的，所以赋值操作只会在访问 C</bar> 的请求中执行。而请求 C</foo>
接口时，我们总是得到空的 C<$foo> 值，因为用户变量未赋值就输出的话，得到
的便是空字符串。

从这个例子我们可以窥见的另一个重要特性是，Nginx 变量名的可见范围虽然是整个
配置
，但每个请求都有所有变量的独立副本，或者说都有各变量用来存放值的容器的独立副本，
彼此互不干扰。比如前面我们请求了 C</bar>
接口后，C<$foo> 变量被赋予了值 C<32>，但它丝毫不会影响后续对 C</foo>
接口的请求所对应的 C<$foo> 值（它仍然是空的！），因为各个请求都有自己独
立的 C<$foo>
变量的副本。

对于 Nginx 新手来说，最常见的错误之一，就是将 Nginx 变量理解成某种
在请求
之间全局共享的东西，或者说“全局变量”。而事实上，Nginx 变量的生命期是不
可能跨越请求边界的。

