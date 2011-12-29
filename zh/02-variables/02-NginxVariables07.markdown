# Nginx 变量漫谈（七） #

在 L<vartut/（一）> 中我们提到过，Nginx 变量的值只有一种类型，
那
就是字符串，但是变量也有可能压根就不存在有意义的值。没有值的变量也有两种特殊的值
：一种是“不合法”（invalid），另一种是“没找到”（not found）。

举例说来，当 Nginx 用户变量 C<$foo> 创建了却未被赋值时，C<$foo>
的值便是“不合法”；而如果当前请求的 URL 参数串中并没有提及 C<XXX>
这个参数，则 L<$arg_XXX> 内建变量的值便是“没找到”。

无论是“不合法”也好，还是“没找到”也罢，这两种 Nginx 变量所拥有
的特
殊值，和空字符串（""）这种取值是完全不同的，比如 JavaScript 语言中
也有专门
的 C<undefined> 和 C<null> 这两种特殊值，而 Lua 语言
中也有专门的 C<nil> 值:
它们既不等同于空字符串，也不等同于数字 C<0>，更不是布尔值 C<false>.
其实 SQL 语言中的 C<NULL> 也是类似的一种东西。

虽然前面在 L<vartut/（一）> 中我们看到，由 L<ngx_rewrite/set>
指令创建的变量未初始化就用在“变量插值”中时，效果等同于空字符串，但那是因为 L<ngx_rewrite/set>
指令为它创建的变量自动注册了一个“取处理程序”，将“不合法”的变量值转换为空字符
串。
为了验证这一点，我们再重新看一下 L<vartut/（一）> 中讨论过的那个例子
：

    :nginx
    location /foo {
        echo "foo = [$foo]";
    }

    location /bar {
        set $foo 32;
        echo "foo = [$foo]";
    }

这里为了简单起见，省略了原先写出的外围 C<server> 配置块。在这个例子
里，我们在 C</bar> 接口中用 L<ngx_rewrite/set> 指令
隐式地创建了 C<$foo> 变量这个名字，然后我们在 C</foo> 接口中不
对 C<$foo> 进行初始化就直接使用 L<ngx_echo/echo> 指令
输出。我们当时测试 C</foo> 接口的结果是

    :bash
    $ curl 'http://localhost:8080/foo'
    foo = []

从输出上看，未初始化的 C<$foo> 变量确实和空字符串的效果等同。但细心的读
者当时应该就已经注意到，对于上面这个请求，Nginx 的错误日志文件（一般文件名
叫做 F<error.log>）中多出一行类似下面这样的警告：

    [warn] 5765#0: *1 using uninitialized "foo" variable, ...

这一行警告是谁输出的呢？答案是 L<ngx_rewrite/set> 指令为 C<$foo>
注册的“取处理程序”。当 C</foo> 接口中的 L<ngx_echo/echo>
指令实
际执行的时候，它会对它的参数 C<"foo = [$foo]"> 进行“变量插值
”计算。于是，参数串中的 C<$foo> 变量会被读取，而 Nginx 会首先检
查其值容器里的取值，结果它看到了“不合法”这个特殊值，于是它这才决定继续调用
C<$foo> 变量的“取处理程序”。于是 C<$foo> 变量的“取处理程序”
开始运行，它向 Nginx 的错误日志打印出上面那条警告消息，然后返回一个空字符
串作为 C<$foo> 的值，并从此缓存在 C<$foo> 的值容器中。

细心的读者会注意到刚刚描述的这个过程其实就是那些支持值缓存的内建变量的工作原理，
只不过 L<ngx_rewrite/set> 指令在这里借用了这套机制来处理未正
确初始化的 Nginx 变量。值得一提的是，只有“不合法”这个特殊值才会触发 Nginx
调用变量的“取处理程序”，而特殊值“没找到”却不会。

上面这样的警告一般会指示出我们的 Nginx 配置中存在变量名拼写错误，抑或是
在错误的场合使用了尚未初始化的变量。因为值缓存的存在，这条警告在一个请
求的生命期中也不会打印多次。当然，L<ngx_rewrite> 模块专门提供了一
条 L<ngx_rewrite/uninitialized_variable_warn>
配置指令可用于禁止这条警告日志。

刚才提到，内建变量 L<$arg_XXX> 在请求 URL 参数 C<XXX>
并不存在时会返回特殊值“找不到”，但遗憾的是在 Nginx 原生配置语言（我们估
且这么称呼它）中是不能很方便地把它和空字符串区分开来的，比如：

    :nginx
    location /test {
        echo "name: [$arg_name]";
    }

这里我们输出 C<$arg_name> 变量的值同时故意在请求中不提供 URL
参数 C<name>:

    :bash
    $ curl 'http://localhost:8080/test'
    name: []

我们看到，输出特殊值“找不到”的效果和空字符串是相同的。因为这一回是 Nginx
的“变量插值”引擎自动把“找不到”给忽略了。

那么我们究竟应当如何捕捉到“找不到”这种特殊值的踪影呢？换句话说，我们应当如何把
它和空字符串给区分开来呢？显然，下面这个请求中，URL 参数 C<name> 是
有值的，而且其值应当是空字符串：

    :bash
    $ curl 'http://localhost:8080/test?name='
    name: []

但我们却无法将之和前面完全不提供 C<name> 参数的情况给区分开。

幸运的是，通过第三方模块 L<ngx_lua>，我们可以轻松地在 Lua 代码中
做到这一点。
请看下面这个例子：

    :nginx
    location /test {
        content_by_lua '
            if ngx.var.arg_name == nil then
                ngx.say("name: missing")
            else
                ngx.say("name: [", ngx.var.arg_name, "]")
            end
        ';
    }

这个例子和前一个例子功能上非常接近，除了我们在 C</test> 接口中使用了
L<ngx_lua>
模块的 L<ngx_lua/content_by_lua> 配置指令，嵌入了一小
段我
们自己的 Lua 代码来对 Nginx 变量 C<$arg_name> 的特殊值
进行
判断。在这个例子中，当 C<$arg_name> 的值为“没找到”（或者“
不合法”）时，C</foo>
接口会输出 C<name: missing> 这一行结果:

    :bash
    curl 'http://localhost:8080/test'
    name: missing

因为这是我们第一次接触到 L<ngx_lua> 模块，所以需要先简单介绍一下。L<ngx_lua>
模块将 Lua 语言解释器（或者 L<LuaJIT|http://luajit.org/luajit.html>
即时编译器）嵌入到了 Nginx 核
心中，从而可以让用户在 Nginx 核心中直接运行 Lua 语言编写的程序。我们
可以选择在 Nginx 不同的请求处理阶段插入我们的 Lua 代码。这些 Lua
代码既可以直接内联在 Nginx 配置文件中，也可以单独放置在外部 F<.lua>
文件里，然后在 Nginx 配置文件中引用 F<.lua> 文件的路径。

回到上面这个例子，我们在 Lua 代码里引用 Nginx 变量都是通过 C<ngx.var>
这个由 L<ngx_lua> 模块提供的 Lua 接口。比如引用 Nginx
变量 C<$VARIABLE> 时，
就在 Lua 代码里写作 L<ngx_lua/ngx.var.VARIABLE>
就可以了。当
Nginx 变量 C<$arg_name> 为特殊值“没找到”（或者“不合法”）时
，
C<ngx.var.arg_name> 在 Lua 世界中的值就是 C<nil>，
即 Lua 语言里的“空”（不同于 Lua 空字符串）。我们在 Lua 里输出
响应体内容的时候，则使用了 L<ngx_lua/ngx.say> 这个 Lua
函数，也是 L<ngx_lua> 模块提供的，功能上等价于 L<ngx_echo>
模块的 L<ngx_echo/echo> 配置指令。

现在，如果我们提供空字符串取值的 C<name> 参数，则输出就和刚才不相同了：

    :bash
    $ curl 'http://localhost:8080/test?name='
    name: []

在这种情况下，Nginx 变量 C<$arg_name> 的取值便是空字符串，这
既不是“没找到”，也不是“不合法”，因此在 Lua 里，C<ngx.var.arg_name>
就返回 Lua 空字符串（""），和刚才的 Lua C<nil> 值就完全区分开
了。

这种区分在有些应用场景下非常重要，比如有的 web service 接口会根
据 C<name> 这个 URL 参数是否存在来决定是否按 C<name> 属性
对数据集合进行过滤，而显然提供空字符串作为 C<name> 参数的值，也会导致对
数
据集中取值为空串的记录进行筛选操作。

不过，标准的 L<$arg_XXX> 变量还是有一些局限，比如我们用下面这个
请求来测试刚才那个 C</test> 接口：

    $ curl 'http://localhost:8080/test?name'
    name: missing

此时，C<$arg_name> 变量仍然读出“找不到”这个特殊值，这就明显有些违
反常识。此外，L<$arg_XXX> 变量在请求 URL 中有多个同名 C<XXX>
参数时，就只会返回最先出现的那个 C<XXX> 参数的值，而默默忽略掉其他实例：

    :bash
    $ curl 'http://localhost:8080/test?name=Tom&name=Jim&name=Bob'
    name: [Tom]

要解决这些局限，可以直接在 Lua 代码中使用 L<ngx_lua> 模块提供的
L<ngx_lua/ngx.req.get_uri_args> 函数。

