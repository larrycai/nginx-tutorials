# Nginx 变量漫谈（五） #

前面在 L<vartut/（二）> 中我们已经了解到变量值容器的生命期是与请求绑
定的，但是我当时有意避开了“请求”
的正式定义。大家应当一直默认这里的“请求”都是指客户端发起的 HTTP 请求。
其实在 Nginx 世界里有两种类型的“请求”，一种叫做“主请求”（main request），
而另一种则叫做“子请求”（subrequest）。我们先来介绍一下它们。

所谓“主请求”，就是由 HTTP 客户端从 Nginx 外部发起的请求。我们前面
见到的所有例子都只涉及到“主请求”，包括那两个使用 L<ngx_echo/echo_exec>
和 L<ngx_rewrite/rewrite> 指令发起“内部跳转”的例子。

而“子请求”则是由 Nginx 正在处理的请求在 Nginx 内部发起的一种
级联请求。“子请求”在外观上很像 HTTP 请求，但实现上却和 HTTP 协议乃
至网络通信一点儿关系都没有。它是 Nginx 内部的一种抽象调用，目的是为了方便
用户把“主请求”的任务分解为多个较小粒度的“内部请求”，并发或串行地访问多个 C<location>
接口，然后由这些 C<location> 接口通力协作，共同完成整个“主请求”。
当然，“子请求”的概念是相对的，任何一个“子请求”也可以再发起更多的“子子请求”
，甚至可以玩递归调用（即自己调用自己）。当一个请求发起一个“子请求”的时候，按照
Nginx 的术语，习惯把前者称为后者的“父请求”（parent request）。
值得一提的是，Apache 服务器中其实
也有“子请求”的概念，所以来自 Apache 世界的读者对此应当不会感到陌生。

下面就来看一个使用了“子请求”的例子：

    :nginx
    location /main {
        echo_location /foo;
        echo_location /bar;
    }

    location /foo {
        echo foo;
    }

    location /bar {
        echo bar;
    }

这里在 C<location /main> 中，通过第三方 L<ngx_echo>
模块的 L<ngx_echo/echo_location> 指令分别发起到 C</foo>
和 C</bar> 这两个接口的 C<GET> 类型的“子请求”。由 L<ngx_echo/echo_location>
发起的“子请求”，其执行是按照配置书写的顺序串行处理的，即只有当 C</foo>
请求处理完毕之后，才会接着处理 C</bar> 请求。这两个“子请求”的输出会按
执行顺序拼接起来，作为 C</main> 接口的最终输出：

    :bash
    $ curl 'http://localhost:8080/main'
    foo
    bar

我们看到，“子请求”方式的通信是在同一个虚拟主机内部进行的，所以 Nginx 核
心在实现“子请求”的时候，就只调用了若干个 C 函数，完全不涉及任何网络或者 UNIX
套接字（socket）通信。我们由此可以看出“子请求”的执行效率是极高的。

回到先前对 Nginx 变量值容器的生命期的讨论，我们现在依旧可以说，它们的
生命期是与当前请求相关联的。每个请求都有所有变量值容器的独立副本，只不过当前
请求既可以是“主请求”，也可以是“子请求”。即便是父子请求之间，同名变量一般也不
会
相互干扰。让我们来通过一个小实验证明一下这个说法：

    :nginx
    location /main {
        set $var main;

        echo_location /foo;
        echo_location /bar;

        echo "main: $var";
    }

    location /foo {
        set $var foo;
        echo "foo: $var";
    }

    location /bar {
        set $var bar;
        echo "bar: $var";
    }

在这个例子中，我们分别在 C</main>，C</foo> 和 C</bar>
这三个 C<location> 配置块中为同一名字的变量，C<$var>，分别设
置
了不同的值并予以输出。特别地，我们在 C</main> 接口中，故意在调用过
C</foo> 和 C</bar> 这两个“子请求”之后，再输出它自己的 C<$var>
变量的值。请求 C</main> 接口的结果是这样的：

    :bash
    $ curl 'http://localhost:8080/main'
    foo: foo
    bar: bar
    main: main

显然，C</foo> 和 C</bar> 这两个“子请求”在处理过程中对变量 C<$var>
各自所做的修改都丝毫没有影响到“主请求” C</main>. 于是这成功印证了
“主请求”以及各个“子请求”都拥有不同的变量 C<$var> 的值容器副本
。

不幸的是，一些 Nginx 模块发起的“子请求”却会自动共享其“父请求”的变
量值容器，比如第三方模块 L<ngx_auth_request>. 下面是一个
例子：

    :nginx
    location /main {
        set $var main;
        auth_request /sub;
        echo "main: $var";
    }

    location /sub {
        set $var sub;
        echo "sub: $var";
    }

这里我们在 C</main> 接口中先为 C<$var> 变量赋初值 C<main>，
然后使用 L<ngx_auth_request> 模块提供的配置指令 L<ngx_auth_request/auth_request>，
发起一个到 C</sub> 接口的“子请求”，最后利用 L<ngx_echo/echo>
指令输出变量 C<$var> 的值。而我们在 C</sub> 接口中则故意把 C<$var>
变量的值改写成 C<sub>. 访问 C</main> 接口的结果如下：

    :bash
    $ curl 'http://localhost:8080/main'
    main: sub

我们看到，C</sub> 接口对 C<$var> 变量值的修改影响到了主请求 C</main>.
所以 L<ngx_auth_request> 模块发起的“子请求”确实是与其“父
请求”共享一套 Nginx 变量的值容器。

对于上面这个例子，相信有读者会问：“为什么‘子请求’ C</sub> 的输出没
有出现在最终的输出里呢？”答案很简单，那就是因为 L<ngx_auth_request/auth_request>
指令会自动忽略“子请求”的响应体，而只检查“子请求”的响应状态码。当状态码是 C<2XX>
的时候，L<ngx_auth_request/auth_request> 指令会
忽略“子请求”而让 Nginx 继续处理当前的请求，否则它就会立即中断当前（主）请
求的执行，返回相应的出错页。在我们的例子中，C</sub> “子请求”只是使用
L<ngx_echo/echo> 指令作了一些输出，所以隐式地返回了指示正常的
C<200> 状态码。

如 L<ngx_auth_request> 模块这样父子请求共享一套 Nginx
变量的行为，虽然可以让父子请求之间的数据双向传递变得极为容易，但是对于足
够复杂的配置，却也经常导致不少难于调试的诡异 bug. 因为用户时常不知道“父
请求”的某个 Nginx 变量的值，其实已经在它的某个“子请求”中被意外修改了。
诸如此类的因共享而导致的不好的“副作用”，让包括 L<ngx_echo>，L<ngx_lua>，
以及 L<ngx_srcache> 在内的许多第三方模块都选择了禁用父子请求间的
变量共享。

