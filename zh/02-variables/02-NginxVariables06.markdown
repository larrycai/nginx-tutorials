# Nginx 变量漫谈（六） #

Nginx 内建变量用在“子请求”的上下文中时，其行为也会变得有些微妙。

前面在 L<vartut/（三）> 中我们已经知道，许多内建变量都不是简单的“存
放值的容器”，它们一般会通过注册“
存取处理程序”来表现得与众不同，而它们即使有存放值的容器，也只是用于缓存“存取处
理程序”的计算结果。我们之前讨论过的 L<ngx_core/$args> 变量正
是通过它的“取处理程序”来返回当前请求的 URL 参数串。因为当前请求也可以是“
子请求”，所以在“子请求”中读取 L<ngx_core/$args>，其“取
处理程序”会很自然地返回当前“子请求”的参数串。我们来看这样的一个例子：

    :nginx
    location /main {
        echo "main args: $args";
        echo_location /sub "a=1&b=2";
    }

    location /sub {
        echo "sub args: $args";
    }

这里在 C</main> 接口中，先用 L<ngx_echo/echo> 指
指令发起子请求 C</sub>. 这里值得注意的是，我们在 L<ngx_echo/echo_location>
语句中除了通过第一个参数指定“子请求”的 URI 之外，还提供了第二个参数，用以
指定该“子请求”的 URL 参数串（即 C<a=1&b=2>）。最后我们定义了
C</sub> 接口，在里面输出了一下 L<ngx_core/$args> 的值
。请求 C</main> 接口的结果如下：

    :bash
    $ curl 'http://localhost:8080/main?c=3'
    main args: c=3
    sub args: a=1&b=2

显然，当 L<ngx_core/$args> 用在“主请求” C</main>
中时
，输出的就是“主请求”的 URL 参数串，C<c=3>；而当用在“子请求” C</sub>
中时，输出
的则是“子请求”的参数串，C<a=1&b=2>。这种行为正符合我们的直觉。

与 L<ngx_core/$args> 类似，内建变量 L<ngx_core/$uri>
用在“子请求”中时，其“取处理程序”也会正确返回当前“子请求”解析过的 URI:

    :nginx
    location /main {
        echo "main uri: $uri";
        echo_location /sub;
    }

    location /sub {
        echo "sub uri: $uri";
    }

请求 C</main> 的结果是

    :bash
    $ curl 'http://localhost:8080/main'
    main uri: /main
    sub uri: /sub

这依然是我们所期望的。

但不幸的是，并非所有的内建变量都作用于当前请求。少数内建变量只作用于“主请求”，
比如由标准模块 L<ngx_http_core> 提供的内建变量 L<ngx_core/$request_method>.

变量 L<ngx_core/$request_method> 在读取时，总是会得
到“主请求”的请求方法，比如 C<GET>、C<POST> 之类。我们来测试一
下：

    :nginx
    location /main {
        echo "main method: $request_method";
        echo_location /sub;
    }

    location /sub {
        echo "sub method: $request_method";
    }

在这个例子里，C</main> 和 C</sub> 接口都会分别输出 L<ngx_core/$request_method>
的值。同时，我们在 C</main> 接口里利用 L<ngx_echo/echo_location>
指令发起一个到 C</sub> 接口的 C<GET> “子请求”。我们现在利用
C<curl> 命令行工具来发起一个到 C</main> 接口的 C<POST>
请求：

    :bash
    $ curl --data hello 'http://localhost:8080/main'
    main method: POST
    sub method: POST

这里我们利用 C<curl> 程序的 C<--data> 选项，指定 C<hello>
作为我们的请求体数据，同时 C<--data> 选项会自动让发送的请求使用 C<POST>
请求方法。测试结果证明了我们先前的
预言，L<ngx_core/$request_method> 变量即使在 C<GET>
“子请求” C</sub> 中使用，得到的值依然是“主请求” C</main>
的请求方法，C<POST>.

有的读者可能觉得我们在这里下的结论有些草率，因为上例是先在“主请求”里读取（并
输出）L<ngx_core/$request_method> 变量，然后才发“
子请求”的，所以这些读者可能认为这并不能排除 L<ngx_core/$request_method>
在进入子请求之前就已经把第一次读到的值给缓存住，从而影响到后续子请求中的输出结
果。不过，这样的顾虑是多余的，因为我们前面在 L<vartut/（五）> 中也特
别提到过，缓存所依赖的变量的值
容器，是与当前请求绑定的，而由 L<ngx_echo> 模块发起的“子请求”都
禁用了父子请求之间的变量共享，所以在上例中，L<ngx_core/$request_method>
内建变量即使真的使用了值容器作为缓存（事实上它也没有），它也不可能影响到 C</sub>
子请求。

为了进一步消除这部分读者的疑虑，我们不妨稍微修改一下刚才那个例子，将 C</main>
接口输出 L<ngx_core/$request_method> 变量的时间推迟
到“子请求”执行完毕之后：

    :nginx
    location /main {
        echo_location /sub;
        echo "main method: $request_method";
    }

    location /sub {
        echo "sub method: $request_method";
    }

让我们重新测试一下：

    :bash
    $ curl --data hello 'http://localhost:8080/main'
    sub method: POST
    main method: POST

可以看到，再次以 C<POST> 方法请求 C</main> 接口的结果与原先那
个例子完全
一致，除了父子请求的输出顺序颠倒了过来（因为我们在本例中交换了 C</main>
接口中那两条输出配置指令的先后次序）。

由此可见，我们并不能通过标准的 L<ngx_core/$request_method>
变量取得“子请求”的请求方法。为了达到我们最初的目的，我们需要求助于第三方模块
L<ngx_echo> 提供的内建变量 L<ngx_echo/$echo_request_method>：

    :nginx
    location /main {
        echo "main method: $echo_request_method";
        echo_location /sub;
    }

    location /sub {
        echo "sub method: $echo_request_method";
    }

此时的输出终于是我们想要的了：

    :bash
    $ curl --data hello 'http://localhost:8080/main'
    main method: POST
    sub method: GET

我们看到，父子请求分别输出了它们各自不同的请求方法，C<POST> 和 C<GET>.

类似 L<ngx_core/$request_method>，内建变量 L<ngx_core/$request_uri>
一般也返回的是“主请求”未经解析过的 URL，毕竟“子请求”都是在 Nginx
内部发起的，并不存在所谓的“未解析的”原始形式。

如果真如前面那部分读者所担心的，内建变量的值缓存在共享变量的父子请求之间起了
作用，
这无疑是灾难性的。我们前面在 L<vartut/（五）> 中已经看到 L<ngx_auth_request>
模块
发起的“子请求”是与其“父请求”共享一套变量的。下面是一个这样的可怕例子
：

    :nginx
    map $uri $tag {
        default     0;
        /main       1;
        /sub        2;
    }

    server {
        listen 8080;

        location /main {
            auth_request /sub;
            echo "main tag: $tag";
        }

        location /sub {
            echo "sub tag: $tag";
        }
    }

这里我们使用久违了的 L<ngx_map/map> 指令来把内建变量 L<ngx_core/$uri>
的值映射到用户变量 C<$tag> 上。当 L<ngx_core/$uri>
的值为 C</main> 时，则赋予 C<$tag> 值 1，当 L<ngx_core/$uri>
取值 C</sub> 时，则赋予 C<$tag> 值 2，其他情况都赋 C<0>.
接着，我们在 C</main> 接口中先用 L<ngx_auth_request>
模块的 L<ngx_auth_request/auth_request> 指令发
起到 C</sub> 接口的子请求，然后再输出变量 C<$tag> 的值。而在
C</sub> 接口中，我们直接输出变量 C<$tag>. 猜猜看，如果我
们访问接口 C</main>，将会得到什么样的输出呢？

    $ curl 'http://localhost:8080/main'
    main tag: 2

咦？我们不是分明把 C</main> 这个值映射到 C<1> 上的么？为什么实际
输出的是 C</sub> 映射的结果 C<2> 呢？

其实道理很简单，因为我们的 C<$tag> 变量在“子请求” C</sub> 中
首先被读取，于是在那里计算出了值 C<2>（因
为 L<ngx_core/$uri> 在那里取值 C</sub>，而根据 L<ngx_map/map>
映射规则，C<$tag> 应当取值 C<2>），从此就被 C<$tag> 的值容
器给缓存住了。而 L<ngx_auth_request/auth_request>
发起的“子请求”又是与“父请求”共享一套变量的，于是当 Nginx 的执行
流回到“父请求”输出 C<$tag> 变量的值时，Nginx 就直接返回缓存住的
结果 C<2>
了。这样的结果确实太意外了。

从这个例子我们再次看到，父子请求间的变量共享，实在不是一个好主意。

