# Nginx 配置指令的执行顺序（一） #

大多数 Nginx 新手都会频繁遇到这样一个困惑，那就是
当同一个 C<location> 配置块使用了多个 Nginx 模块的
配置指令时，这些指令的执行顺序很可能会
跟它们的书写顺序大相径庭。于是许多人选择了“试错法”，然后他们的配置文件
就时常被改得一片狼藉。这个系列的教程就旨在帮助读者逐步地理解这些配置指令背后的执
行时间和
先后顺序的奥秘。

现在就来看这样一个令人困惑的例子：

    :nginx
    ? location /test {
    ?     set $a 32;
    ?     echo $a;
    ?
    ?     set $a 56;
    ?     echo $a;
    ? }

从这个例子的本意来看，我们期望的输出是一行 C<32> 和一行 C<56>，
因为我们第一次用 L<ngx_echo/echo> 配置指令输出了 C<$a>
变量的值以后，又紧接着使用 L<ngx_rewrite/set> 配置指令修改了
C<$a>. 然而不幸的是，事实并非如此：

    :bash
    $ curl 'http://localhost:8080/test
    56
    56

我们看到，语句 C<set $a 56> 似乎在第一条 C<echo $a> 语
句之前就执行过了。这究竟是为什么呢？难道我们遇到了 Nginx 中的一个 bug？

显然，这里并没有 Nginx 的 bug；要理解这里发生的事情，就首先需要
知道 Nginx 处理每一个用户请求时，都是按照若干个不同阶段（phase）
依次处理的。

Nginx 的请求处理阶段共有 11 个之多，我们先介绍其中 3 个比较常见的。
按照它们
执行时的先后顺序，依次是 C<rewrite> 阶段、C<access> 阶段
以及 C<content> 阶段（后面我们还有机会见到其他更多的处理阶段）。

所有 Nginx 模块提供的配置指令一般只会注册并运行在其中的某一个处理阶段。比
如上例中的 L<ngx_rewrite/set> 指令就是在 C<rewrite>
阶段运行的，而 L<ngx_echo/echo> 指令就只会在 C<content>
阶段运行。前面我们已经知道，在单个请求的处理过程中，C<rewrite> 阶段总
是在 C<content> 阶段之前执行，因此属于 C<rewrite> 阶段的
配置指令也总是会无条件地在 C<content> 阶段的配置指令之前执行。于是
在同一个 C<location> 配置块中，L<ngx_rewrite/set>
指令总是会在 L<ngx_echo/echo> 指令之前执行，即使我们在配置文件
中有意把 L<ngx_rewrite/set>
语句写在 L<ngx_echo/echo> 语句的后面。

回到刚才那个例子，

    :nginx
    set $a 32;
    echo $a;

    set $a 56;
    echo $a;

实际的执行顺序应当是

    :nginx
    set $a 32;
    set $a 56;
    echo $a;
    echo $a;

即先在 C<rewrite> 阶段执行完这里的两条 L<ngx_rewrite/set>
赋值语句，然后再在后面的 C<content> 阶段依次执行那两条 L<ngx_echo/echo>
语句。分属两个不同处理阶段的配置指令之间是不能穿插着运行的。

为了进一步验证这一点，我们不妨借助 Nginx 的“调试日志”（debug log）来一窥
Nginx 的实际执行过程。

因为这是我们第一次提及 Nginx 的“调试日志”，所以有必要先简单介绍一下它的
启用
方法。“调试日志”默认是禁用的，因为它会引入比较大的运行时开销，让 Nginx 服务
器显著变慢。一般我们需要重新编译和构造 Nginx 可执行文件，并且在调用 Nginx
源码包提供的 C<./configure> 脚本时传入 C<--with-debug>
命令行选项。例如我们下载完 Nginx 源码包后在 Linux 或者 Mac
OS X 等系统上构建时，典型的步骤是这样的：

    :bash
    tar xvf nginx-1.0.10.tar.gz
    cd nginx-1.0.10/
    ./configure --with-debug
    make
    sudu make install

如果你使用的是我维护的 L<ngx_openresty|http://openresty.org>
软件包，则同样可以向
它的 C<./configure> 脚本传递 C<--with-debug>
命令行选项。

当我们启用 C<--with-debug> 选项重新构建好调试版的 Nginx
之后，还需要同时在配置文件中通过标准的 L<error_log> 配置指令为
错误日
志使用 C<debug> 日志级别（这同时也是最低的日志级别）：

    :nginx
    error_log logs/error.log debug;

这里重要的是 L<error_log> 指令的第二个参数，C<debug>，而前
面第一个参数是错误日志文件的
路径，F<logs/error.log>. 当然，你也可以指定其他路径，但
后面
我们会检查这个文件的内容，所以请特别留意一下这里实际
配置的文件路径。

现在我们重新启动 Nginx（注意，如果 Nginx 可执行文件也被更新过，仅仅
让 Nginx 重新加载配置是不够的，需要关闭再启动 Nginx 主服务进程），
然后再请求一
下我们刚才那个示例接口：

    :bash
    $ curl 'http://localhost:8080/test'
    56
    56

现在可以检查一下前面配置的 Nginx 错误日志文件中的输出。因为文件中的输
出比较多（在我的机器上有 700 多行），所以不妨用 C<grep> 命令在终
端上过滤出我们感兴趣的部分：

    :bash
    grep -E 'http (output filter|script (set|value))' logs/error.log

在我机器上的输出是这个样子的（为了方便呈现，这里对 C<grep> 命令的实
际输出作
了一些简单的编辑，略去了每一行的行首时间戳）：

    :text
    [debug] 5363#0: *1 http script value: "32"
    [debug] 5363#0: *1 http script set $a
    [debug] 5363#0: *1 http script value: "56"
    [debug] 5363#0: *1 http script set $a
    [debug] 5363#0: *1 http output filter "/test?"
    [debug] 5363#0: *1 http output filter "/test?"
    [debug] 5363#0: *1 http output filter "/test?"

这里需要稍微解释一下这些调试信息的具体含义。L<ngx_rewrite/set>
配置指令在实际运行时
会打印出两行以 C<http script> 起始的调试信息，其中第一行信息是
L<ngx_rewrite/set> 语句中被赋予的值，而第二行则是 L<ngx_rewrite/set>
语句中被赋值的 Nginx 变量名。于是上面首先过滤出来的

    :text
    [debug] 5363#0: *1 http script value: "32"
    [debug] 5363#0: *1 http script set $a

这两行就对应我们例子中的配置语句

    :nginx
    set $a 32;

而接下来这两行调试信息

    :text
    [debug] 5363#0: *1 http script value: "56"
    [debug] 5363#0: *1 http script set $a

则对应配置语句

    :nginx
    set $a 56;

此外，凡在 Nginx 中输出响应体数据时，都会调用 Nginx 的所谓“
输出过滤器”（output filter），我们一直在使用的 L<ngx_echo/echo>
指令自然也不例外。而一旦调用 Nginx 的“输出过滤器”，便会产生类似下面这样
的调试信息：

    :text
    [debug] 5363#0: *1 http output filter "/test?"

当然，这里的 C<"/test?"> 部分对于其他接口可能会发生变化，因为它显示
的是当前请求
的 URI. 这样联系起来看，就不难发现，上例中的那两条 L<ngx_rewrite/set>
语句确实都是在那两条 L<ngx_echo/echo> 语句之前执行的。

细心的读者可能会问，为什么这个例子明明只使用了两条 L<ngx_echo/echo>
语句进行输出
，但却有三行 C<http output filter> 调试信息呢？其实，前
两行 C<http output filter> 信息确实分别对应那两条
L<ngx_echo/echo> 语句，而最后那一行信息则是对应 L<ngx_echo>
模块输出指示响应体末尾的结
束标记。正是为了输出这个特殊的结束标记，才会多出一次对 Nginx “输出过滤器
”的调用。包括 L<ngx_proxy> 在内的许多模块在输出响应体数据流时都具
有此
种行为。

现在我们就不会再为前面那个例子输出两行一模一样的 C<56> 而感到惊讶了。我们
根本没有机会在第二条 L<ngx_rewrite/set> 语句之前用 L<ngx_echo/echo>
输出。幸运的是，仍然可以借助一些小技巧来达到最初的目的：

    :nginx
    location /test {
        set $a 32;
        set $saved_a $a;
        set $a 56;

        echo $saved_a;
        echo $a;
    }

此时的输出便符合那个问题示例的初衷了：

    :bash
    $ curl 'http://localhost:8080/test'
    32
    56

这里通过引入新的用户变量 C<$saved_a>，在改写 C<$a> 之前及时
保存了 C<$a> 的初始值。而对于多条 L<ngx_rewrite/set>
指令而
言，它们之间的执行顺序是由 L<ngx_rewrite> 模块来保证与书写
顺序相一致的。
同理，L<ngx_echo> 模块自身也会保证它的多条 L<ngx_echo/echo>
指令之间的执行顺序。

细心的读者应当发现，我们在 L<Nginx 变量漫谈系列> 的示例中已经广泛使用
了这种技巧，来绕过因处理阶段而引起的指令执行顺序上的限制。

看到这里，有的读者可能会问：“那么我在使用一条陌生的配置指令之前，如何知道它究竟
运行
在哪一个处理阶段呢？”答案是：查看该指令的文档（当然，高级开发人员也可以直接查看
模
块的 C 源码）。在许多模块的文档
中，都会专门标记其配置指令所运行的具体阶段。例如 L<ngx_echo/echo>
指令的文档中有这么一行：

    :text
    phase: content

这一行便是说，当前配置指令运行在 C<content> 阶段。如果你使用的
Nginx 模块碰巧没有指示运行阶段的文档，可以直接联系该模块的作者请求补充。不
过，值得一提的是，并非所有的配置指令都与某个处理阶段相关联，例如我们先前在 L<vartut/Nginx
变量漫谈（一）> 中提到过的 L<ngx_geo/geo> 指令以及在 L<vartut/Nginx
变量漫谈（四）> 中介绍过的 L<ngx_map/map> 指令。这些不与处理阶
段相关联的配置指令基本上都是“声明性的”（declarative），
即不直接产生某种动作或者过程。Nginx 的作者 Igor Sysoev 在公开
场合曾不止一次地强调，Nginx
配置文件所使用的语言本质上是“声明性的”，而非“过程性
的”（procedural）。

